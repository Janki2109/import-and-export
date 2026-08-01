import '../core/network/api_client.dart';

class NotificationService {
  final ApiClient _client = ApiClient();

  Future<List<dynamic>> list() async {
    final res = await _client.get('/notifications');
    return res.data['data'] as List? ?? [];
  }

  Future<void> markRead(String id) async {
    await _client.post('/notifications/$id/read');
  }

  Future<void> registerDevice({required String token, required String platform}) async {
    await _client.post('/notifications/register-device', data: {
      'token': token,
      'platform': platform,
    });
  }
}
