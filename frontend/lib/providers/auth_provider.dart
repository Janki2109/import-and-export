import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants/app_constants.dart';
import '../core/network/api_client.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/company_service.dart';
import '../services/kyc_service.dart';
import '../services/push_notification_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  final _authService = AuthService();
  final _companyService = CompanyService();
  final _kycService = KYCService();

  AuthStatus status = AuthStatus.unknown;
  AppUser? currentUser;
  String? errorMessage;
  bool isLoading = false;

  /// Onboarding gate state — null means "not checked yet" (router waits rather than
  /// bouncing the user prematurely). Populated right after auth resolves.
  bool? companyExists;
  bool? kycSubmitted;
  // BUG FIX (Journey 2 — KYC gate): the router previously only checked whether a KYC row
  // existed (kycSubmitted), so a rejected or still-pending user could reach the full dashboard
  // after submitting once. kycStatus carries the real status ('submitted'/'verified'/'rejected')
  // so the router can gate on actual approval instead.
  String? kycStatus;

  AuthProvider() {
    // ApiClient calls this if a token refresh fails (refresh token itself expired/revoked),
    // so a session that dies mid-use still lands the user back on the login screen.
    ApiClient.onSessionExpired = () {
      currentUser = null;
      status = AuthStatus.unauthenticated;
      notifyListeners();
    };
  }

  /// Refreshes company/KYC onboarding flags — called after login/auto-login and again
  /// after each onboarding step completes, so the router's redirect always sees fresh state.
  Future<void> refreshOnboardingStatus() async {
    try {
      final company = await _companyService.getMine();
      companyExists = company != null;
    } catch (_) {
      companyExists = false;
    }
    try {
      final kyc = await _kycService.getMyStatus();
      kycSubmitted = kyc['id'] != null;
      kycStatus = kyc['status'] as String?;
    } catch (_) {
      kycSubmitted = false;
      kycStatus = null;
    }
    notifyListeners();
  }

  /// Called once at app startup — checks secure storage for an existing session.
  Future<void> tryAutoLogin() async {
    final token = await _storage.read(key: AppConstants.tokenKey);
    final role = await _storage.read(key: AppConstants.roleKey);
    final userId = await _storage.read(key: AppConstants.userIdKey);
    final userName = await _storage.read(key: AppConstants.userNameKey);

    if (token != null && role != null && userId != null) {
      currentUser = AppUser(
        id: userId,
        role: roleFromString(role),
        fullName: userName ?? '',
        email: '',
        phone: '',
        isActive: true,
      );
      status = AuthStatus.authenticated;
      PushNotificationService().init();
      await refreshOnboardingStatus();
    } else {
      status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final (user, accessToken, refreshToken) = await _authService.login(email, password);
      await _storage.write(key: AppConstants.tokenKey, value: accessToken);
      await _storage.write(key: AppConstants.refreshTokenKey, value: refreshToken);
      await _storage.write(key: AppConstants.roleKey, value: roleToString(user.role));
      await _storage.write(key: AppConstants.userIdKey, value: user.id);
      await _storage.write(key: AppConstants.userNameKey, value: user.fullName);

      currentUser = user;
      status = AuthStatus.authenticated;
      PushNotificationService().init();
      await refreshOnboardingStatus();
      isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      errorMessage = 'Login failed. Please try again.';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String role,
    required String fullName,
    String? companyName,
    required String email,
    required String phone,
    required String password,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _authService.register(
        role: role,
        fullName: fullName,
        companyName: companyName,
        email: email,
        phone: phone,
        password: password,
      );
      isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      errorMessage = 'Registration failed. Please try again.';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Called by the Profile module after a successful edit, so the cached user (used for
  /// greetings/app-bar titles elsewhere) reflects the change immediately without requiring
  /// a re-login. Purely local state — does not touch the auth session itself.
  void applyProfileUpdate(AppUser updated) {
    currentUser = updated;
    notifyListeners();
  }

  Future<void> logout() async {
    final refreshToken = await _storage.read(key: AppConstants.refreshTokenKey);
    if (refreshToken != null) {
      try {
        await _authService.logout(refreshToken);
      } catch (_) {
        // best-effort — local session is cleared regardless
      }
    }
    await _storage.deleteAll();
    currentUser = null;
    companyExists = null;
    kycSubmitted = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
