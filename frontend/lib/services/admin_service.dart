import '../core/network/api_client.dart';
import '../models/admin.dart';

class AdminService {
  final ApiClient _client = ApiClient();

  Future<List<AdminUser>> listUsers({String? role}) async {
    final res = await _client.get('/admin/users', query: role != null ? {'role': role} : null);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminUser.fromJson(e)).toList();
  }

  Future<void> setUserActive(String userId, bool active) async {
    await _client.post('/admin/users/active/$userId', data: {'active': active});
  }

  Future<List<AdminUserRow>> listUsersRich({String? role}) async {
    final res = await _client.get('/admin/users/rich', query: role != null ? {'role': role} : null);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminUserRow.fromJson(e)).toList();
  }

  Future<void> deleteUser(String userId) async {
    await _client.dio.delete('/admin/users/$userId');
  }

  Future<List<dynamic>> listOrders({String? status}) async {
    final res = await _client.get('/admin/orders', query: status != null ? {'status': status} : null);
    return res.data['data'] as List? ?? [];
  }

  Future<List<AdminOrderRow>> listOrdersRich({String? status}) async {
    final res = await _client.get('/admin/orders/rich', query: status != null ? {'status': status} : null);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminOrderRow.fromJson(e)).toList();
  }

  Future<List<AdminQuotationRow>> listQuotations() async {
    final res = await _client.get('/admin/quotations');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminQuotationRow.fromJson(e)).toList();
  }

  Future<List<AdminWalletRow>> listWallets() async {
    final res = await _client.get('/admin/wallets');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminWalletRow.fromJson(e)).toList();
  }

  Future<List<AdminWithdrawalRow>> listWithdrawals() async {
    final res = await _client.get('/admin/withdrawals');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminWithdrawalRow.fromJson(e)).toList();
  }

  Future<void> approveWithdrawal(String entryId) async {
    await _client.post('/admin/withdrawals/approve/$entryId');
  }

  Future<void> rejectWithdrawal(String entryId, String reason) async {
    await _client.post('/admin/withdrawals/reject/$entryId', data: {'reason': reason});
  }

  Future<Analytics> getAnalytics() async {
    final res = await _client.get('/admin/analytics');
    return Analytics.fromJson(res.data['data']);
  }

  Future<ChartAnalytics> getChartAnalytics() async {
    final res = await _client.get('/admin/analytics/charts');
    return ChartAnalytics.fromJson(res.data['data']);
  }

  Future<List<AdminRFQRow>> listAllRFQs() async {
    final res = await _client.get('/admin/rfqs');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminRFQRow.fromJson(e)).toList();
  }

  Future<void> deleteRFQ(String id) async {
    await _client.dio.delete('/admin/rfqs/$id');
  }

  Future<List<AdminShipmentRow>> listAllShipments() async {
    final res = await _client.get('/admin/shipments');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminShipmentRow.fromJson(e)).toList();
  }

  Future<List<FraudSignal>> getFraudSignals() async {
    final res = await _client.get('/admin/fraud-signals');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => FraudSignal.fromJson(e)).toList();
  }

  Future<void> moderateProduct(String productId, bool active) async {
    await _client.post('/admin/products/$productId/moderate', data: {'active': active});
  }

  Future<void> createHSCode({required String code, required String description, required String chapter, double bcd = 0, double igst = 18}) async {
    await _client.post('/admin/hs-codes', data: {
      'code': code, 'description': description, 'chapter': chapter,
      'basic_customs_duty_percent': bcd, 'igst_percent': igst,
    });
  }

  Future<void> deleteHSCode(String id) async {
    await _client.dio.delete('/admin/hs-codes/$id');
  }

  Future<void> createCountry({required String name, required String iso2, required String iso3, required String region, bool restricted = false, String? notes}) async {
    await _client.post('/admin/countries', data: {
      'name': name, 'iso2': iso2, 'iso3': iso3, 'region': region, 'is_restricted': restricted, 'notes': notes,
    });
  }

  Future<void> setCountryRestricted(String id, bool restricted) async {
    await _client.post('/admin/countries/$id/restrict', data: {'restricted': restricted});
  }

  Future<void> deleteCountry(String id) async {
    await _client.dio.delete('/admin/countries/$id');
  }

  // ---- Escrow (Admin Escrow Wallet) ----

  Future<List<EscrowOrderRow>> listEscrowOrders({String? status}) async {
    final res = await _client.get('/admin/escrow', query: status != null ? {'status': status} : null);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => EscrowOrderRow.fromJson(e)).toList();
  }

  Future<EscrowSummary> getEscrowSummary() async {
    final res = await _client.get('/admin/escrow/summary');
    return EscrowSummary.fromJson(res.data['data']);
  }

  Future<void> releaseEscrowPayment(String orderId) async {
    await _client.post('/admin/escrow/release/$orderId');
  }

  Future<void> holdEscrowPayment(String orderId) async {
    await _client.post('/admin/escrow/hold/$orderId');
  }

  Future<void> refundEscrowPayment(String orderId, String reason) async {
    await _client.post('/admin/escrow/refund/$orderId', data: {'reason': reason});
  }

  Future<List<dynamic>> getEscrowHistory(String orderId) async {
    final res = await _client.get('/admin/escrow/history/$orderId');
    return res.data['data'] as List? ?? [];
  }

  // ---- KYC review (existing backend endpoints, admin-only) ----

  Future<List<dynamic>> listPendingKYC() async {
    final res = await _client.get('/kyc/pending');
    return res.data['data'] as List? ?? [];
  }

  Future<void> approveKYC(String userId) async {
    await _client.post('/kyc/approve', data: {'user_id': userId});
  }

  Future<void> rejectKYC(String userId, String reason) async {
    await _client.post('/kyc/reject', data: {'user_id': userId, 'reason': reason});
  }

  // ---- Disputes review ----

  Future<List<dynamic>> listPendingDisputes() async {
    final res = await _client.get('/disputes/pending');
    return res.data['data'] as List? ?? [];
  }

  Future<void> resolveDispute(String disputeId, String resolution, String notes) async {
    await _client.post('/disputes/$disputeId/resolve', data: {'resolution': resolution, 'notes': notes});
  }

  Future<List<dynamic>> listAuditLogs() async {
    final res = await _client.get('/audit-logs');
    return res.data['data'] as List? ?? [];
  }

  // ---- Settings ----

  Future<PlatformSettings> getSettings() async {
    final res = await _client.get('/admin/settings');
    return PlatformSettings.fromJson(res.data['data']);
  }

  Future<void> updateSettings({
    required String appName,
    String? logoUrl,
    String? supportEmail,
    required String currency,
    String? smtpHost,
    int? smtpPort,
    String? smtpUsername,
    String? smtpPassword,
    String? smtpFrom,
  }) async {
    await _client.put('/admin/settings', data: {
      'app_name': appName,
      'logo_url': logoUrl,
      'support_email': supportEmail,
      'currency': currency,
      'smtp_host': smtpHost,
      'smtp_port': smtpPort,
      'smtp_username': smtpUsername,
      'smtp_password': smtpPassword,
      'smtp_from': smtpFrom,
    });
  }

  // ---- Notification broadcast ----

  Future<Map<String, dynamic>> broadcastNotification({
    String? targetRole,
    required String title,
    required String body,
    required bool inApp,
    required bool email,
  }) async {
    final res = await _client.post('/admin/notifications/broadcast', data: {
      'target_role': targetRole,
      'title': title,
      'body': body,
      'in_app': inApp,
      'email': email,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  // ---- Logistics Management ----

  Future<List<AdminLogisticsRow>> listLogistics() async {
    final res = await _client.get('/admin/logistics');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminLogisticsRow.fromJson(e)).toList();
  }

  // ---- Chat Management ----

  Future<List<AdminConversationRow>> listConversations() async {
    final res = await _client.get('/admin/chats');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminConversationRow.fromJson(e)).toList();
  }

  Future<List<dynamic>> getConversationMessages(String conversationId) async {
    final res = await _client.get('/admin/chats/messages/$conversationId');
    return res.data['data'] as List? ?? [];
  }

  Future<void> archiveConversation(String conversationId, bool archived) async {
    await _client.post('/admin/chats/archive/$conversationId', data: {'archived': archived});
  }

  Future<void> blockUser(String userId) async {
    await _client.post('/admin/users/block/$userId');
  }

  // ---- Global Search ----

  Future<List<AdminSearchResult>> globalSearch(String query) async {
    final res = await _client.get('/admin/search', query: {'q': query});
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminSearchResult.fromJson(e)).toList();
  }
}
