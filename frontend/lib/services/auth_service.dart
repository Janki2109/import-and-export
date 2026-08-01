import '../core/network/api_client.dart';
import '../models/user.dart';

class AuthService {
  final ApiClient _client = ApiClient();

  Future<Map<String, dynamic>> register({
    required String role,
    required String fullName,
    String? companyName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final res = await _client.post('/auth/register', data: {
      'role': role,
      'full_name': fullName,
      'company_name': companyName,
      'email': email,
      'phone': phone,
      'password': password,
    });
    return res.data['data'];
  }

  /// Returns (user, accessToken, refreshToken)
  Future<(AppUser, String, String)> login(String email, String password) async {
    final res = await _client.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    final data = res.data['data'];
    final user = AppUser.fromJson(data['user']);
    final accessToken = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String;
    return (user, accessToken, refreshToken);
  }

  Future<void> logout(String refreshToken) async {
    await _client.post('/auth/logout', data: {'refresh_token': refreshToken});
  }
}
