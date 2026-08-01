/// One negotiation — 1:1 with the quotation it's attached to.
class Negotiation {
  final String id;
  final String rfqId;
  final String quotationId;
  final String importerId;
  final String exporterId;
  final String status; // open | accepted | rejected | expired | closed
  final int currentRound;
  final DateTime createdAt;
  final DateTime updatedAt;

  Negotiation({
    required this.id,
    required this.rfqId,
    required this.quotationId,
    required this.importerId,
    required this.exporterId,
    required this.status,
    required this.currentRound,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Negotiation.fromJson(Map<String, dynamic> json) => Negotiation(
        id: json['id'],
        rfqId: json['rfq_id'],
        quotationId: json['quotation_id'],
        importerId: json['importer_id'],
        exporterId: json['exporter_id'],
        status: json['status'],
        currentRound: json['current_round'] ?? 1,
        createdAt: DateTime.parse(json['created_at']),
        updatedAt: DateTime.parse(json['updated_at']),
      );
}

/// One entry in the structured negotiation timeline — the initial quote, every counter
/// offer, and the final accepted offer are all rows of this same shape.
class NegotiationOffer {
  final String id;
  final String negotiationId;
  final int roundNumber;
  final String createdBy; // importer | exporter
  final String createdByUserId;
  final double unitPrice;
  final String currency;
  final double quantity;
  final double? moq;
  final double totalPrice;
  final int? deliveryDays;
  final int? dispatchDays;
  final String? shippingMode;
  final String? incoterm;
  final String? paymentTerms;
  final String? packaging;
  final DateTime? validityDate;
  final String? specialConditions;
  final String? remarks;
  final String status; // pending | accepted | rejected | countered
  final DateTime createdAt;

  NegotiationOffer({
    required this.id,
    required this.negotiationId,
    required this.roundNumber,
    required this.createdBy,
    required this.createdByUserId,
    required this.unitPrice,
    required this.currency,
    required this.quantity,
    this.moq,
    required this.totalPrice,
    this.deliveryDays,
    this.dispatchDays,
    this.shippingMode,
    this.incoterm,
    this.paymentTerms,
    this.packaging,
    this.validityDate,
    this.specialConditions,
    this.remarks,
    required this.status,
    required this.createdAt,
  });

  factory NegotiationOffer.fromJson(Map<String, dynamic> json) => NegotiationOffer(
        id: json['id'],
        negotiationId: json['negotiation_id'],
        roundNumber: json['round_number'],
        createdBy: json['created_by'],
        createdByUserId: json['created_by_user_id'],
        unitPrice: (json['unit_price'] as num).toDouble(),
        currency: json['currency'] ?? 'INR',
        quantity: (json['quantity'] as num).toDouble(),
        moq: (json['moq'] as num?)?.toDouble(),
        totalPrice: (json['total_price'] as num).toDouble(),
        deliveryDays: json['delivery_days'],
        dispatchDays: json['dispatch_days'],
        shippingMode: json['shipping_mode'],
        incoterm: json['incoterm'],
        paymentTerms: json['payment_terms'],
        packaging: json['packaging'],
        validityDate: json['validity_date'] != null ? DateTime.parse(json['validity_date']) : null,
        specialConditions: json['special_conditions'],
        remarks: json['remarks'],
        status: json['status'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// Admin negotiations list row — GET /admin/negotiations.
class AdminNegotiationRow {
  final String id;
  final String status;
  final int currentRound;
  final String rfqNumber;
  final String importerName;
  final String exporterName;
  final String productName;
  final int offerCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  AdminNegotiationRow({
    required this.id,
    required this.status,
    required this.currentRound,
    required this.rfqNumber,
    required this.importerName,
    required this.exporterName,
    required this.productName,
    required this.offerCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AdminNegotiationRow.fromJson(Map<String, dynamic> json) => AdminNegotiationRow(
        id: json['id'],
        status: json['status'],
        currentRound: json['current_round'] ?? 1,
        rfqNumber: json['rfq_number'],
        importerName: json['importer_name'],
        exporterName: json['exporter_name'],
        productName: json['product_name'],
        offerCount: json['offer_count'] ?? 0,
        createdAt: DateTime.parse(json['created_at']),
        updatedAt: DateTime.parse(json['updated_at']),
      );
}
