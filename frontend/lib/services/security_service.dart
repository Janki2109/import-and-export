import '../core/network/api_client.dart';
import '../models/security.dart';

/// Security Dashboard + device management — additive module, mirrors the new backend
/// /security/* endpoints. Never touches auth/login itself (that stays in AuthService).
class SecurityService {
  final ApiClient _client = ApiClient();

  Future<SecurityOverview> getOverview() async {
    final res = await _client.get('/security/overview');
    return SecurityOverview.fromJson(res.data['data']);
  }

  Future<List<SecurityDevice>> listDevices() async {
    final res = await _client.get('/security/devices');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => SecurityDevice.fromJson(e)).toList();
  }

  Future<void> trustDevice(String deviceRowId) async {
    await _client.post('/security/devices/$deviceRowId/trust');
  }

  Future<void> logoutDevice(String deviceRowId) async {
    await _client.post('/security/devices/$deviceRowId/logout');
  }

  Future<void> logoutAllDevices() async {
    await _client.post('/auth/logout-all');
  }
}
