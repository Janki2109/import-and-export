import '../core/network/api_client.dart';
import '../models/user.dart';

class ProfileService {
  final ApiClient _client = ApiClient();

  Future<AppUser> getProfile() async {
    final res = await _client.get('/users/me');
    return AppUser.fromJson(res.data['data']);
  }

  Future<AppUser> updateProfile({
    required String fullName,
    required String email,
    required String phone,
    String? avatarUrl,
  }) async {
    final res = await _client.put('/users/me', data: {
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'avatar_url': avatarUrl,
    });
    return AppUser.fromJson(res.data['data']);
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await _client.post('/users/me/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  /// Trimmed public profile for another user (no email/phone) — used to show
  /// "Importer: <name>" / "Exporter: <name>" on shared screens like Order Details.
  Future<PublicUser> getPublicProfile(String userId) async {
    final res = await _client.get('/users/public/$userId');
    return PublicUser.fromJson(res.data['data']);
  }
}

class PublicUser {
  final String id;
  final String fullName;
  final String? companyName;
  final String role;
  final String? avatarUrl;

  PublicUser({required this.id, required this.fullName, this.companyName, required this.role, this.avatarUrl});

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
        id: json['id'],
        fullName: json['full_name'],
        companyName: json['company_name'],
        role: json['role'],
        avatarUrl: json['avatar_url'],
      );
}
