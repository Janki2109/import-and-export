import '../core/network/api_client.dart';
import '../models/order.dart';

class OrderService {
  final ApiClient _client = ApiClient();

  /// Creates the order server-side. Returns {order, upi_link, amount} — the upi_link
  /// (upi://pay?...) is launched next to open the importer's UPI app (GPay/PhonePe/etc).
  Future<Map<String, dynamic>> createOrder({
    required String exporterId,
    required String productName,
    String? hsnCode,
    required double quantity,
    required String unit,
    required double unitPrice,
    String? deliveryAddress,
    String? notes,
  }) async {
    final res = await _client.post('/orders', data: {
      'exporter_id': exporterId,
      'product_name': productName,
      'hsn_code': hsnCode,
      'quantity': quantity,
      'unit': unit,
      'unit_price': unitPrice,
      'delivery_address': deliveryAddress,
      'notes': notes,
    });
    return res.data['data'];
  }

  /// Called when the importer taps "Payment Done" after returning from their UPI app.
  /// Self-declared — no gateway signature involved.
  Future<void> confirmPayment({required String orderId}) async {
    await _client.post('/orders/confirm-payment', data: {'order_id': orderId});
  }

  /// Importer confirms goods received -> escrow released (payout processed manually by the platform).
  Future<void> confirmDelivery({required String orderId}) async {
    await _client.post('/orders/confirm-delivery', data: {'order_id': orderId});
  }

  Future<Shipment?> getShipmentByOrder(String orderId) async {
    final res = await _client.get('/shipments/by-order/$orderId');
    final data = res.data['data'];
    if (data == null) return null;
    return Shipment.fromJson(data);
  }

  Future<void> assignLogistics({
    required String orderId,
    required String logisticsId,
    required String trackingNumber,
    required String carrierName,
  }) async {
    await _client.post('/shipments/assign', data: {
      'order_id': orderId,
      'logistics_id': logisticsId,
      'tracking_number': trackingNumber,
      'carrier_name': carrierName,
    });
  }

  Future<void> updateShipmentStatus({
    required String shipmentId,
    required String status,
    String? location,
    String? remarks,
  }) async {
    await _client.post('/shipments/update-status', data: {
      'shipment_id': shipmentId,
      'status': status,
      'location': location ?? '',
      'remarks': remarks ?? '',
    });
  }

  Future<void> uploadPOD({
    required String shipmentId,
    required String fileUrl,
    String? remarks,
  }) async {
    await _client.post('/shipments/upload-pod', data: {
      'shipment_id': shipmentId,
      'file_url': fileUrl,
      'file_type': 'image',
      'remarks': remarks,
    });
  }

  Future<List<Shipment>> myShipments() async {
    final res = await _client.get('/shipments/mine');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => Shipment.fromJson(e)).toList();
  }

  /// Tracking timeline — every status change recorded for a shipment, oldest first.
  Future<List<ShipmentEvent>> getTimeline(String shipmentId) async {
    final res = await _client.get('/shipments/$shipmentId/timeline');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => ShipmentEvent.fromJson(e)).toList();
  }

  /// Escrow status for this order (importer/exporter only) — powers the "Awaiting Buyer
  /// Confirmation — Auto Release Due In X Days" banner on Order Details.
  Future<EscrowStatusInfo?> getEscrowStatus(String orderId) async {
    try {
      final res = await _client.get('/orders/$orderId/escrow');
      final data = res.data['data'];
      if (data == null) return null;
      return EscrowStatusInfo.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
