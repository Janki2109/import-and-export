import '../core/network/api_client.dart';
import '../models/compliance.dart';

/// Compliance Center — additive module. Every call here hits a new endpoint added
/// specifically for this feature; nothing here touches RFQ/Order/Escrow/Wallet APIs.
class ComplianceService {
  final ApiClient _client = ApiClient();

  Future<OrderComplianceChecklist> getForOrder(String orderId) async {
    final res = await _client.get('/orders/$orderId/compliance');
    return OrderComplianceChecklist.fromJson(res.data['data']);
  }

  Future<void> uploadDocument({required String complianceId, required String fileUrl, String? remarks}) async {
    await _client.post('/compliance/upload/$complianceId', data: {'file_url': fileUrl, 'remarks': remarks});
  }

  Future<List<ComplianceDocumentHistoryEntry>> getHistory(String complianceId) async {
    final res = await _client.get('/compliance/history/$complianceId');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => ComplianceDocumentHistoryEntry.fromJson(e)).toList();
  }

  // ---- Admin ----

  Future<List<AdminComplianceRow>> adminList({String? status, String? orderId, String? country, String? search}) async {
    final res = await _client.get('/admin/compliance', query: {
      if (status != null) 'status': status,
      if (orderId != null) 'order_id': orderId,
      if (country != null) 'country': country,
      if (search != null) 'search': search,
    });
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminComplianceRow.fromJson(e)).toList();
  }

  Future<ComplianceSummary> adminSummary() async {
    final res = await _client.get('/admin/compliance/summary');
    return ComplianceSummary.fromJson(res.data['data']);
  }

  Future<void> verifyDocument(String complianceId) async {
    await _client.post('/admin/compliance/verify/$complianceId');
  }

  Future<void> rejectDocument(String complianceId, String remarks) async {
    await _client.post('/admin/compliance/reject/$complianceId', data: {'remarks': remarks});
  }

  Future<List<ComplianceRule>> listRules() async {
    final res = await _client.get('/admin/compliance-rules');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => ComplianceRule.fromJson(e)).toList();
  }

  Future<void> createRule({
    String? originCountry,
    String? destinationCountry,
    String? hsCode,
    String? shippingMode,
    required String documentName,
    required String responsibleRole,
    required bool mandatory,
    int displayOrder = 0,
    String? description,
  }) async {
    await _client.post('/admin/compliance-rules', data: {
      'origin_country': originCountry,
      'destination_country': destinationCountry,
      'hs_code': hsCode,
      'shipping_mode': shippingMode,
      'document_name': documentName,
      'responsible_role': responsibleRole,
      'mandatory': mandatory,
      'display_order': displayOrder,
      'description': description,
    });
  }

  Future<void> deleteRule(String id) async {
    await _client.delete('/admin/compliance-rules/$id');
  }
}
