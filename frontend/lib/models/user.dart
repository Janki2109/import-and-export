enum UserRole { importer, exporter, logistics, admin }

UserRole roleFromString(String s) {
  switch (s) {
    case 'importer':
      return UserRole.importer;
    case 'exporter':
      return UserRole.exporter;
    case 'logistics':
      return UserRole.logistics;
    default:
      return UserRole.admin;
  }
}

String roleToString(UserRole r) => r.name;

class AppUser {
  final String id;
  final UserRole role;
  final String fullName;
  final String? companyName;
  final String email;
  final String phone;
  final String? avatarUrl;
  final bool isActive;

  AppUser({
    required this.id,
    required this.role,
    required this.fullName,
    this.companyName,
    required this.email,
    required this.phone,
    this.avatarUrl,
    required this.isActive,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'],
        role: roleFromString(json['role']),
        fullName: json['full_name'],
        companyName: json['company_name'],
        email: json['email'],
        phone: json['phone'],
        avatarUrl: json['avatar_url'],
        isActive: json['is_active'] ?? true,
      );
}
