import '../core/network/api_client.dart';
import '../models/payment_terms.dart';

/// Payment Terms & Milestone Escrow Engine — additive module. Every call here hits a new
/// endpoint added specifically for this feature; nothing here touches Order/Escrow/Wallet APIs.
class PaymentTermsService {
  final ApiClient _client = ApiClient();

  Future<(PaymentTerms, List<PaymentMilestone>)> setup({
    required String orderId,
    required String paymentModel,
    String currency = 'INR',
    List<Map<String, dynamic>>? milestones,
    String? lcNumber,
    String? lcBankName,
    DateTime? lcExpiryDate,
    int? openAccountDays,
  }) async {
    final res = await _client.post('/payment-terms/setup', data: {
      'order_id': orderId,
      'payment_model': paymentModel,
      'currency': currency,
      'milestones': milestones,
      'lc_number': lcNumber,
      'lc_bank_name': lcBankName,
      'lc_expiry_date': lcExpiryDate?.toIso8601String().substring(0, 10),
      'open_account_days': openAccountDays,
    });
    final terms = PaymentTerms.fromJson(res.data['data']['payment_terms']);
    final ms = ((res.data['data']['milestones'] as List?) ?? []).map((e) => PaymentMilestone.fromJson(e)).toList();
    return (terms, ms);
  }

  /// Null if payment terms haven't been set up for this order yet.
  Future<(PaymentTerms, List<PaymentMilestone>)?> getByOrder(String orderId) async {
    try {
      final res = await _client.get('/payment-terms/by-order/$orderId');
      final terms = PaymentTerms.fromJson(res.data['data']['payment_terms']);
      final ms = ((res.data['data']['milestones'] as List?) ?? []).map((e) => PaymentMilestone.fromJson(e)).toList();
      return (terms, ms);
    } catch (_) {
      return null;
    }
  }

  Future<void> payMilestone(String milestoneId) async {
    await _client.post('/payment-terms/milestones/$milestoneId/pay');
  }

  Future<void> uploadProof(String milestoneId, String proofUrl) async {
    await _client.post('/payment-terms/milestones/$milestoneId/proof', data: {'proof_url': proofUrl});
  }

  Future<void> updateLC({
    required String paymentTermsId,
    String? lcNumber,
    String? lcBankName,
    DateTime? lcExpiryDate,
    String? lcStatus,
  }) async {
    await _client.put('/payment-terms/$paymentTermsId/lc', data: {
      'lc_number': lcNumber,
      'lc_bank_name': lcBankName,
      'lc_expiry_date': lcExpiryDate?.toIso8601String().substring(0, 10),
      'lc_status': lcStatus,
    });
  }

  // ---- Admin ----

  Future<void> approve(String milestoneId, {String? remarks}) async {
    await _client.post('/payment-terms/milestones/$milestoneId/approve', data: {'remarks': remarks});
  }

  Future<void> reject(String milestoneId, {String? remarks}) async {
    await _client.post('/payment-terms/milestones/$milestoneId/reject', data: {'remarks': remarks});
  }

  Future<void> hold(String milestoneId, {String? remarks}) async {
    await _client.post('/payment-terms/milestones/$milestoneId/hold', data: {'remarks': remarks});
  }

  Future<void> unhold(String milestoneId) async {
    await _client.post('/payment-terms/milestones/$milestoneId/unhold');
  }

  Future<void> release(String milestoneId) async {
    await _client.post('/payment-terms/milestones/$milestoneId/release');
  }

  Future<List<AdminPaymentRow>> adminList({String? paymentModel, String? search}) async {
    final res = await _client.get('/admin/payment-terms', query: {
      if (paymentModel != null) 'payment_model': paymentModel,
      if (search != null) 'search': search,
    });
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminPaymentRow.fromJson(e)).toList();
  }

  Future<AdminPaymentSummary> adminSummary() async {
    final res = await _client.get('/admin/payment-terms/summary');
    return AdminPaymentSummary.fromJson(res.data['data']);
  }
}
