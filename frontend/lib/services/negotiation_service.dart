import '../core/network/api_client.dart';
import '../models/negotiation.dart';

/// Negotiation Engine — additive module. Every call here hits a new endpoint added
/// specifically for this feature; nothing here touches RFQ/Quotation/Order APIs.
class NegotiationService {
  final ApiClient _client = ApiClient();

  Future<void> rejectQuotation(String quotationId) async {
    await _client.post('/negotiations/reject-quotation', data: {'quotation_id': quotationId});
  }

  Future<Negotiation> start(String quotationId) async {
    final res = await _client.post('/negotiations/start', data: {'quotation_id': quotationId});
    return Negotiation.fromJson(res.data['data']);
  }

  /// Null if no negotiation has been started for this quotation yet.
  Future<Negotiation?> getByQuotation(String quotationId) async {
    final res = await _client.get('/negotiations/by-quotation/$quotationId');
    final data = res.data['data'];
    if (data == null) return null;
    return Negotiation.fromJson(data);
  }

  Future<Negotiation> getById(String negotiationId) async {
    final res = await _client.get('/negotiations/detail/$negotiationId');
    return Negotiation.fromJson(res.data['data']);
  }

  Future<List<NegotiationOffer>> getHistory(String negotiationId) async {
    final res = await _client.get('/negotiations/history/$negotiationId');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => NegotiationOffer.fromJson(e)).toList();
  }

  Future<List<Negotiation>> listMine() async {
    final res = await _client.get('/negotiations/mine');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => Negotiation.fromJson(e)).toList();
  }

  Future<NegotiationOffer> counterOffer({
    required String negotiationId,
    required double unitPrice,
    String currency = 'INR',
    required double quantity,
    double? moq,
    int? deliveryDays,
    int? dispatchDays,
    String? shippingMode,
    String? incoterm,
    String? paymentTerms,
    String? packaging,
    DateTime? validityDate,
    String? specialConditions,
    String? remarks,
  }) async {
    final res = await _client.post('/negotiations/counter/$negotiationId', data: {
      'unit_price': unitPrice,
      'currency': currency,
      'quantity': quantity,
      'moq': moq,
      'delivery_days': deliveryDays,
      'dispatch_days': dispatchDays,
      'shipping_mode': shippingMode,
      'incoterm': incoterm,
      'payment_terms': paymentTerms,
      'packaging': packaging,
      'validity_date': validityDate?.toIso8601String().substring(0, 10),
      'special_conditions': specialConditions,
      'remarks': remarks,
    });
    return NegotiationOffer.fromJson(res.data['data']);
  }

  Future<void> acceptOffer(String negotiationId) async {
    await _client.post('/negotiations/accept/$negotiationId');
  }

  Future<void> rejectOffer(String negotiationId) async {
    await _client.post('/negotiations/reject/$negotiationId');
  }

  Future<void> closeNegotiation(String negotiationId) async {
    await _client.post('/negotiations/close/$negotiationId');
  }

  // ---- Admin ----

  Future<List<AdminNegotiationRow>> adminList({String? status, String? search}) async {
    final res = await _client.get('/admin/negotiations', query: {
      if (status != null) 'status': status,
      if (search != null) 'search': search,
    });
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdminNegotiationRow.fromJson(e)).toList();
  }

  Future<void> adminForceClose(String negotiationId) async {
    await _client.post('/admin/negotiations/force-close/$negotiationId');
  }
}
