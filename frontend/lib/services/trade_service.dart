import '../core/network/api_client.dart';
import '../models/trade.dart';
import '../models/order.dart';

/// Covers RFQ -> Quotation -> Order flow, Wallet, and trade document generation.
class TradeService {
  final ApiClient _client = ApiClient();

  // ---------------- RFQ ----------------

  Future<RFQ> createRFQ({
    required String productName,
    String? hsnCode,
    required double quantity,
    required String unit,
    double? targetPrice,
    required String destinationCountry,
    String? description,
    String? productImageUrl,
    List<String>? targetExporterIds,
  }) async {
    final res = await _client.post('/rfqs', data: {
      'product_name': productName,
      'hsn_code': hsnCode,
      'quantity': quantity,
      'unit': unit,
      'target_price': targetPrice,
      'destination_country': destinationCountry,
      'description': description,
      'product_image_url': productImageUrl,
      'target_exporter_ids': targetExporterIds,
    });
    return RFQ.fromJson(res.data['data']);
  }

  Future<List<RFQ>> listOpenRFQs() async {
    final res = await _client.get('/rfqs');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => RFQ.fromJson(e)).toList();
  }

  Future<List<RFQ>> listMyRFQs() async {
    final res = await _client.get('/rfqs/mine');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => RFQ.fromJson(e)).toList();
  }

  /// Added for the Negotiation Engine's "My Negotiations" list (needs the RFQ's product
  /// name/number for context) — uses the existing, unmodified GET /rfqs/:id endpoint.
  Future<RFQ> getRFQ(String id) async {
    final res = await _client.get('/rfqs/$id');
    return RFQ.fromJson(res.data['data']);
  }

  // ---------------- Quotation ----------------

  Future<Quotation> submitQuotation({
    required String rfqId,
    required double unitPrice,
    required double quantity,
    required DateTime validityDate,
    String? terms,
  }) async {
    final res = await _client.post('/quotations', data: {
      'rfq_id': rfqId,
      'unit_price': unitPrice,
      'quantity': quantity,
      'validity_date': validityDate.toIso8601String().substring(0, 10),
      'terms': terms,
    });
    return Quotation.fromJson(res.data['data']);
  }

  Future<List<Quotation>> listQuotationsForRFQ(String rfqId) async {
    final res = await _client.get('/rfqs/$rfqId/quotations');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => Quotation.fromJson(e)).toList();
  }

  Future<List<Quotation>> listMyQuotations() async {
    final res = await _client.get('/quotations/mine');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => Quotation.fromJson(e)).toList();
  }

  /// Accepting a quotation creates the order + escrow row server-side.
  Future<Order> acceptQuotation(String quotationId, {String? deliveryAddress, String? notes}) async {
    final res = await _client.post('/quotations/$quotationId/accept', data: {
      'delivery_address': deliveryAddress,
      'notes': notes,
    });
    return Order.fromJson(res.data['data']['order']);
  }

  // ---------------- Wallet ----------------

  Future<WalletSummary> getMyWallet() async {
    final res = await _client.get('/wallet/me');
    return WalletSummary.fromJson(res.data['data']);
  }

  /// Pays out wallet balance to the user's linked bank/UPI account (set up via KYC approval).
  Future<void> withdraw(double amount) async {
    await _client.post('/wallet/withdraw', data: {'amount': amount});
  }

  // ---------------- Documents ----------------

  Future<TradeDocument> generateDocument({required String orderId, required String type}) async {
    final res = await _client.post('/documents/generate', data: {
      'order_id': orderId,
      'type': type,
    });
    return TradeDocument.fromJson(res.data['data']);
  }

  Future<List<TradeDocument>> listDocumentsForOrder(String orderId) async {
    final res = await _client.get('/documents/by-order/$orderId');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => TradeDocument.fromJson(e)).toList();
  }

  /// Journey 9 — version history for one document.
  Future<List<TradeDocumentVersion>> listDocumentVersions(String documentId) async {
    final res = await _client.get('/documents/$documentId/versions');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => TradeDocumentVersion.fromJson(e)).toList();
  }

  Future<void> deleteDocument(String documentId) async {
    await _client.delete('/documents/$documentId');
  }
}
