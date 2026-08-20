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
  // See ApiClient's _storage field doc for why resetOnError is needed on Android.
  final _storage = const FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: true));
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
      // BUG FIX (H-5): getMine()/getMyStatus() already signal "genuinely not onboarded" with a
      // normal successful response (data == null / no KYC row) — reaching this catch block means
      // the request itself failed (timeout, DNS, 5xx), not that onboarding is incomplete.
      // Previously this forced companyExists = false, which the router (app_router.dart) treats
      // identically to "confirmed not onboarded" and redirects to the create-company screen —
      // a transient network hiccup at login could bounce a fully-onboarded user back into
      // onboarding. Leave the flag at its "not checked yet" null state instead, which the router
      // already treats as "wait" rather than "redirect".
      companyExists = null;
    }
    try {
      final kyc = await _kycService.getMyStatus();
      kycSubmitted = kyc['id'] != null;
      kycStatus = kyc['status'] as String?;
    } catch (_) {
      kycSubmitted = null;
      kycStatus = null;
    }
    notifyListeners();
  }

  /// Called once at app startup — checks secure storage for an existing session.
  Future<void> tryAutoLogin() async {
    try {
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
    } catch (_) {
      // Secure storage can throw (e.g. PlatformException) if the keystore is unavailable or
      // corrupted. Fall through to unauthenticated rather than leaving status stuck at
      // `unknown`, which would strand the user on the splash screen forever.
      status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password, {String? role}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final (user, accessToken, refreshToken) = await _authService.login(email, password, role: role);
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
    await PushNotificationService().unregisterCurrentDevice();
    final refreshToken = await _storage.read(key: AppConstants.refreshTokenKey);
    if (refreshToken != null) {
      try {
        await _authService.logout(refreshToken);
      } catch (_) {
        // best-effort — local session is cleared regardless
      }
    }
    // BUG FIX (H-4): deleteAll() wiped every FlutterSecureStorage entry, including the chat
    // end-to-end encryption private key (chat_e2e_service.dart) — its own contract comment says
    // this key is "generated exactly once per device install", but a routine logout regenerated
    // it, permanently losing the ability to decrypt every previously-received chat message. Only
    // clear the auth-session keys that logout is actually responsible for.
    await _storage.delete(key: AppConstants.tokenKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
    await _storage.delete(key: AppConstants.roleKey);
    await _storage.delete(key: AppConstants.userIdKey);
    await _storage.delete(key: AppConstants.userNameKey);
    currentUser = null;
    companyExists = null;
    kycSubmitted = null;
    kycStatus = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  @override
  void dispose() {
    // BUG FIX (L-7): onSessionExpired is a single static slot shared by every ApiClient call
    // app-wide — nulling it here served no purpose (AuthProvider lives for the app's lifetime;
    // dispose() only runs at app teardown) and only created the failure mode the field's own
    // doc comment warns about: if a second AuthProvider instance were ever created, this line
    // would wipe out ITS constructor-installed handler, breaking session-expiry handling
    // globally. Simply not clearing it here removes that fragility with no behavior change for
    // the single-instance case this app actually uses.
    super.dispose();
  }
}
