import 'trade.dart';

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

  // Uploaded with the RFQ — productImageUrl is a real backend field (RFQ.productImageUrl);
  // certificationDocumentUrl isn't (no dedicated column), so it's recovered from the
  // `description` text the same way the other "extra" fields below are — see fromRFQ.
  final String? productImageUrl;
  final String? certificationDocumentUrl;

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
    this.productImageUrl,
    this.certificationDocumentUrl,
  });

  /// Reconstructs the full detail set for an already-posted RFQ from the real backend
  /// record: fields with a dedicated column (productName, hsnCode, quantity, unit,
  /// targetPrice, destinationCountry, productImageUrl, status, rfqNumber, createdAt) come
  /// straight off [rfq]; the rest were folded into `description` as "Key: value" lines by
  /// CreateRFQScreen's _buildDescription() and are parsed back out here — the exact inverse
  /// of that encoding, so this never invents/hardcodes a value that wasn't actually entered.
  factory RfqReportData.fromRFQ(
    RFQ rfq, {
    required String buyerName,
    required String buyerCompany,
    required String buyerEmail,
  }) {
    const prefixToKey = {
      'Category: ': 'category',
      'Min. Order Qty: ': 'minOrderQty',
      'Packaging Type: ': 'packagingType',
      'Incoterm: ': 'incoterm',
      'Currency: ': 'currency',
      'Origin Country: ': 'originCountry',
      'Preferred Shipping Mode: ': 'shippingMode',
      'Delivery Deadline: ': 'deliveryDeadline',
      'Quality Requirements: ': 'qualityRequirements',
      'Certifications Required: ': 'certifications',
      'Certification Document: ': 'certificationDocumentUrl',
      'Inspection Required: ': 'inspectionRequired',
      'Packaging Instructions: ': 'packagingInstructions',
      'Additional Notes: ': 'additionalNotes',
    };

    final parsed = <String, String>{};
    final baseLines = <String>[];
    for (final line in (rfq.description ?? '').split('\n')) {
      String? matchedPrefix;
      for (final p in prefixToKey.keys) {
        if (line.startsWith(p)) {
          matchedPrefix = p;
          break;
        }
      }
      if (matchedPrefix == null) {
        if (line.trim().isNotEmpty) baseLines.add(line);
      } else {
        parsed[prefixToKey[matchedPrefix]!] = line.substring(matchedPrefix.length);
      }
    }

    return RfqReportData(
      rfqNumber: rfq.rfqNumber,
      issueDate: '${rfq.createdAt.toLocal()}'.split('.').first,
      status: rfq.status.isNotEmpty ? rfq.status[0].toUpperCase() + rfq.status.substring(1) : 'Unknown',
      buyerName: buyerName,
      buyerCompany: buyerCompany,
      buyerEmail: buyerEmail,
      supplierName: rfq.status == 'quoted' || rfq.status == 'closed' ? 'See quotations for assigned supplier' : 'To be assigned (open RFQ)',
      productName: rfq.productName,
      hsnCode: rfq.hsnCode ?? 'Not specified',
      category: parsed['category'] ?? 'Not specified',
      productDescription: baseLines.join('\n').trim().isEmpty ? 'Not specified' : baseLines.join('\n').trim(),
      quantity: rfq.quantity.toString(),
      unit: rfq.unit,
      minOrderQty: parsed['minOrderQty'] ?? 'Not specified',
      packagingType: parsed['packagingType'] ?? 'Not specified',
      targetPrice: rfq.targetPrice?.toStringAsFixed(2) ?? 'Not specified',
      currency: parsed['currency'] ?? 'INR',
      incoterm: parsed['incoterm'] ?? 'Not specified',
      originCountry: parsed['originCountry'] ?? 'Not specified',
      destinationCountry: rfq.destinationCountry,
      shippingMode: parsed['shippingMode'] ?? 'Not specified',
      deliveryDeadline: parsed['deliveryDeadline'] ?? 'Not specified',
      qualityRequirements: parsed['qualityRequirements'] ?? '',
      certifications: parsed['certifications'] ?? '',
      inspectionRequired: parsed['inspectionRequired'] == 'Yes',
      packagingInstructions: parsed['packagingInstructions'] ?? '',
      additionalNotes: parsed['additionalNotes'] ?? '',
      productImageUrl: rfq.productImageUrl,
      certificationDocumentUrl: parsed['certificationDocumentUrl'],
    );
  }

  static const termsAndConditions =
      'This RFQ is a request for quotation only and does not constitute a binding purchase order. '
      'Prices, quantities, and delivery terms are subject to negotiation and confirmation by both '
      'parties. Payment is held in escrow via the platform and released only after delivery is '
      'confirmed. All goods must comply with applicable import/export regulations of the origin and '
      'destination countries.';
}
