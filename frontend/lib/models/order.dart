class Order {
  final String id;
  final String orderNumber;
  final String importerId;
  final String exporterId;
  final String productName;
  final String? hsnCode;
  final double quantity;
  final String unit;
  final double unitPrice;
  final String currency;
  final double totalAmount;
  final double platformFeeAmount;
  final double exporterPayoutAmount;
  final String status;
  final int autoReleaseDays;
  final String? deliveryAddress;
  final String? notes;
  final DateTime createdAt;

  Order({
    required this.id,
    required this.orderNumber,
    required this.importerId,
    required this.exporterId,
    required this.productName,
    this.hsnCode,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.currency,
    required this.totalAmount,
    required this.platformFeeAmount,
    required this.exporterPayoutAmount,
    required this.status,
    required this.autoReleaseDays,
    this.deliveryAddress,
    this.notes,
    required this.createdAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'],
        orderNumber: json['order_number'],
        importerId: json['importer_id'],
        exporterId: json['exporter_id'],
        productName: json['product_name'],
        hsnCode: json['hsn_code'],
        quantity: (json['quantity'] as num).toDouble(),
        unit: json['unit'],
        unitPrice: (json['unit_price'] as num).toDouble(),
        currency: json['currency'] ?? 'INR',
        totalAmount: (json['total_amount'] as num).toDouble(),
        platformFeeAmount: (json['platform_fee_amount'] as num?)?.toDouble() ?? 0,
        exporterPayoutAmount: (json['exporter_payout_amount'] as num?)?.toDouble() ?? 0,
        status: json['status'],
        autoReleaseDays: json['auto_release_days'] ?? 7,
        deliveryAddress: json['delivery_address'],
        notes: json['notes'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class Shipment {
  final String id;
  final String orderId;
  final String? logisticsId;
  final String? trackingNumber;
  final String status;
  final String? carrierName;
  final String? pickupAddress;
  final String? deliveryAddress;
  final DateTime? estimatedDelivery;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  Shipment({
    required this.id,
    required this.orderId,
    this.logisticsId,
    this.trackingNumber,
    required this.status,
    this.carrierName,
    this.pickupAddress,
    this.deliveryAddress,
    this.estimatedDelivery,
    this.pickedUpAt,
    this.deliveredAt,
  });

  factory Shipment.fromJson(Map<String, dynamic> json) => Shipment(
        id: json['id'],
        orderId: json['order_id'],
        logisticsId: json['logistics_id'],
        trackingNumber: json['tracking_number'],
        status: json['status'],
        carrierName: json['carrier_name'],
        pickupAddress: json['pickup_address'],
        deliveryAddress: json['delivery_address'],
        estimatedDelivery: json['estimated_delivery'] != null ? DateTime.parse(json['estimated_delivery']) : null,
        pickedUpAt: json['picked_up_at'] != null ? DateTime.parse(json['picked_up_at']) : null,
        deliveredAt: json['delivered_at'] != null ? DateTime.parse(json['delivered_at']) : null,
      );
}

class ShipmentEvent {
  final String id;
  final String shipmentId;
  final String status;
  final String? location;
  final String? remarks;
  final DateTime createdAt;

  ShipmentEvent({
    required this.id,
    required this.shipmentId,
    required this.status,
    this.location,
    this.remarks,
    required this.createdAt,
  });

  factory ShipmentEvent.fromJson(Map<String, dynamic> json) => ShipmentEvent(
        id: json['id'],
        shipmentId: json['shipment_id'],
        status: json['status'],
        location: json['location'],
        remarks: json['remarks'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// Escrow status for the order's own importer/exporter — powers the "Awaiting Buyer
/// Confirmation — Auto Release Due In X Days" banner on Order Details.
class EscrowStatusInfo {
  final String status;
  final DateTime? heldAt;
  final DateTime? releaseDueAt;
  final DateTime? releasedAt;
  final DateTime? refundedAt;

  EscrowStatusInfo({required this.status, this.heldAt, this.releaseDueAt, this.releasedAt, this.refundedAt});

  factory EscrowStatusInfo.fromJson(Map<String, dynamic> json) => EscrowStatusInfo(
        status: json['status'],
        heldAt: json['held_at'] != null ? DateTime.parse(json['held_at']) : null,
        releaseDueAt: json['release_due_at'] != null ? DateTime.parse(json['release_due_at']) : null,
        releasedAt: json['released_at'] != null ? DateTime.parse(json['released_at']) : null,
        refundedAt: json['refunded_at'] != null ? DateTime.parse(json['refunded_at']) : null,
      );
}
