/// Everything shown on an RFQ preview / report — some fields map straight to the real
/// backend RFQ record (rfqNumber, productName, hsnCode, quantity, unit, targetPrice,
/// destinationCountry), the rest (category, incoterm, shipping mode, etc.) are additional
/// details captured purely for the document — see create_rfq_screen.dart for how they're
/// folded into the existing `description` field before the (unchanged) POST /rfqs call.
class RfqReportData {
  final String rfqNumber;
  final String issueDate;
  final String status;

  final String buyerName;
  final String buyerCompany;
  final String buyerEmail;
  final String supplierName;

  final String productName;
  final String hsnCode;
  final String category;
  final String productDescription;

  final String quantity;
  final String unit;
  final String minOrderQty;
  final String packagingType;

  final String targetPrice;
  final String currency;
  final String incoterm;

  final String originCountry;
  final String destinationCountry;
  final String shippingMode;
  final String deliveryDeadline;

  final String qualityRequirements;
  final String certifications;
  final bool inspectionRequired;
  final String packagingInstructions;
  final String additionalNotes;

  const RfqReportData({
    required this.rfqNumber,
    required this.issueDate,
    required this.status,
    required this.buyerName,
    required this.buyerCompany,
    required this.buyerEmail,
    required this.supplierName,
    required this.productName,
    required this.hsnCode,
    required this.category,
    required this.productDescription,
    required this.quantity,
    required this.unit,
    required this.minOrderQty,
    required this.packagingType,
    required this.targetPrice,
    required this.currency,
    required this.incoterm,
    required this.originCountry,
    required this.destinationCountry,
    required this.shippingMode,
    required this.deliveryDeadline,
    required this.qualityRequirements,
    required this.certifications,
    required this.inspectionRequired,
    required this.packagingInstructions,
    required this.additionalNotes,
  });

  static const termsAndConditions =
      'This RFQ is a request for quotation only and does not constitute a binding purchase order. '
      'Prices, quantities, and delivery terms are subject to negotiation and confirmation by both '
      'parties. Payment is held in escrow via the platform and released only after delivery is '
      'confirmed. All goods must comply with applicable import/export regulations of the origin and '
      'destination countries.';
}
