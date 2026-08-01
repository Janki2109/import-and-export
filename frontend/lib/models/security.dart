/// Security Dashboard models — mirror backend/internal/services/security_service.go's
/// SecurityOverview and repository.Device/LoginHistoryEntry/DocumentAccessLogEntry.
class SecurityDevice {
  final String id;
  final String deviceId;
  final String? deviceName;
  final String? platform;
  final bool trusted;
  final bool isActive;
  final DateTime lastSeen;
  final String? lastIp;
  final String? lastCountry;

  SecurityDevice({
    required this.id,
    required this.deviceId,
    this.deviceName,
    this.platform,
    required this.trusted,
    required this.isActive,
    required this.lastSeen,
    this.lastIp,
    this.lastCountry,
  });

  factory SecurityDevice.fromJson(Map<String, dynamic> json) => SecurityDevice(
        id: json['ID'] ?? json['id'],
        deviceId: json['DeviceID'] ?? json['device_id'] ?? '',
        deviceName: json['DeviceName'] ?? json['device_name'],
        platform: json['Platform'] ?? json['platform'],
        trusted: json['Trusted'] ?? json['trusted'] ?? false,
        isActive: json['IsActive'] ?? json['is_active'] ?? true,
        lastSeen: DateTime.parse(json['LastSeen'] ?? json['last_seen']),
        lastIp: json['LastIP'] ?? json['last_ip'],
        lastCountry: json['LastCountry'] ?? json['last_country'],
      );
}

class LoginHistoryEntry {
  final bool success;
  final String ip;
  final String? deviceId;
  final String? country;
  final DateTime createdAt;

  LoginHistoryEntry({required this.success, required this.ip, this.deviceId, this.country, required this.createdAt});

  factory LoginHistoryEntry.fromJson(Map<String, dynamic> json) => LoginHistoryEntry(
        success: json['Success'] ?? json['success'] ?? false,
        ip: json['IP'] ?? json['ip'] ?? '',
        deviceId: json['DeviceID'] ?? json['device_id'],
        country: json['Country'] ?? json['country'],
        createdAt: DateTime.parse(json['CreatedAt'] ?? json['created_at']),
      );
}

class DocumentAccessEntry {
  final String storageKey;
  final String action;
  final DateTime createdAt;

  DocumentAccessEntry({required this.storageKey, required this.action, required this.createdAt});

  factory DocumentAccessEntry.fromJson(Map<String, dynamic> json) => DocumentAccessEntry(
        storageKey: json['StorageKey'] ?? json['storage_key'] ?? '',
        action: json['Action'] ?? json['action'] ?? '',
        createdAt: DateTime.parse(json['CreatedAt'] ?? json['created_at']),
      );
}

class SecurityOverview {
  final int securityScore;
  final String passwordStrength;
  final bool mfaEnabled;
  final bool emailVerified;
  final bool phoneVerified;
  final int activeDevices;
  final DateTime? lastLoginAt;
  final List<SecurityDevice> devices;
  final List<LoginHistoryEntry> loginHistory;
  final List<DocumentAccessEntry> recentDocumentAccess;

  SecurityOverview({
    required this.securityScore,
    required this.passwordStrength,
    required this.mfaEnabled,
    required this.emailVerified,
    required this.phoneVerified,
    required this.activeDevices,
    this.lastLoginAt,
    required this.devices,
    required this.loginHistory,
    required this.recentDocumentAccess,
  });

  factory SecurityOverview.fromJson(Map<String, dynamic> json) => SecurityOverview(
        securityScore: json['security_score'] ?? 0,
        passwordStrength: json['password_strength'] ?? '',
        mfaEnabled: json['mfa_enabled'] ?? false,
        emailVerified: json['email_verified'] ?? false,
        phoneVerified: json['phone_verified'] ?? false,
        activeDevices: json['active_devices'] ?? 0,
        lastLoginAt: json['last_login_at'] != null ? DateTime.tryParse(json['last_login_at']) : null,
        devices: ((json['devices'] as List?) ?? []).map((e) => SecurityDevice.fromJson(e)).toList(),
        loginHistory: ((json['login_history'] as List?) ?? []).map((e) => LoginHistoryEntry.fromJson(e)).toList(),
        recentDocumentAccess: ((json['recent_document_access'] as List?) ?? []).map((e) => DocumentAccessEntry.fromJson(e)).toList(),
      );
}
