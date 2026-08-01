/// One checklist item on an order — GET /orders/:id/compliance.
class OrderComplianceItem {
  final String id;
  final String orderId;
  final String documentName;
  final String responsibleRole; // importer | exporter | logistics
  final bool mandatory;
  final int displayOrder;
  final String? description;
  final String status; // pending | uploaded | verified | rejected
  final String? uploadedFile;
  final String? remarks;
  final String? verifiedByAdmin;
  final DateTime? uploadedAt;
  final DateTime? verifiedAt;
  final DateTime createdAt;

  OrderComplianceItem({
    required this.id,
    required this.orderId,
    required this.documentName,
    required this.responsibleRole,
    required this.mandatory,
    required this.displayOrder,
    this.description,
    required this.status,
    this.uploadedFile,
    this.remarks,
    this.verifiedByAdmin,
    this.uploadedAt,
    this.verifiedAt,
    required this.createdAt,
  });

  factory OrderComplianceItem.fromJson(Map<String, dynamic> json) => OrderComplianceItem(
        id: json['id'],
        orderId: json['order_id'],
        documentName: json['document_name'],
        responsibleRole: json['responsible_role'],
        mandatory: json['mandatory'] ?? true,
        displayOrder: json['display_order'] ?? 0,
        description: json['description'],
        status: json['status'],
        uploadedFile: json['uploaded_file'],
        remarks: json['remarks'],
        verifiedByAdmin: json['verified_by_admin'],
        uploadedAt: json['uploaded_at'] != null ? DateTime.parse(json['uploaded_at']) : null,
        verifiedAt: json['verified_at'] != null ? DateTime.parse(json['verified_at']) : null,
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// Full response of GET /orders/:id/compliance — checklist + progress + block status.
class OrderComplianceChecklist {
  final List<OrderComplianceItem> items;
  final int progressPercent;
  final bool shipmentBlocked;
  final List<String> missingMandatory;

  OrderComplianceChecklist({
    required this.items,
    required this.progressPercent,
    required this.shipmentBlocked,
    required this.missingMandatory,
  });

  factory OrderComplianceChecklist.fromJson(Map<String, dynamic> json) => OrderComplianceChecklist(
        items: ((json['items'] as List?) ?? []).map((e) => OrderComplianceItem.fromJson(e)).toList(),
        progressPercent: json['progress_percent'] ?? 0,
        shipmentBlocked: json['shipment_blocked'] ?? false,
        missingMandatory: ((json['missing_mandatory'] as List?) ?? []).map((e) => e.toString()).toList(),
      );
}

/// One upload/re-upload event — GET /compliance/history/:id.
class ComplianceDocumentHistoryEntry {
  final String id;
  final String fileUrl;
  final String uploadedBy;
  final String? remarks;
  final DateTime createdAt;

  ComplianceDocumentHistoryEntry({
    required this.id,
    required this.fileUrl,
    required this.uploadedBy,
    this.remarks,
    required this.createdAt,
  });

  factory ComplianceDocumentHistoryEntry.fromJson(Map<String, dynamic> json) => ComplianceDocumentHistoryEntry(
        id: json['id'],
        fileUrl: json['file_url'],
        uploadedBy: json['uploaded_by'],
        remarks: json['remarks'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// Admin Compliance Center row — GET /admin/compliance.
class AdminComplianceRow {
  final String id;
  final String orderId;
  final String orderNumber;
  final String documentName;
  final String responsibleRole;
  final bool mandatory;
  final String status;
  final String importerName;
  final String exporterName;
  final String? logisticsName;
  final String? originCountry;
  final String? destinationCountry;
  final String? uploadedFile;
  final String? remarks;
  final DateTime? uploadedAt;
  final DateTime? verifiedAt;
  final DateTime createdAt;

  AdminComplianceRow({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.documentName,
    required this.responsibleRole,
    required this.mandatory,
    required this.status,
    required this.importerName,
    required this.exporterName,
    this.logisticsName,
    this.originCountry,
    this.destinationCountry,
    this.uploadedFile,
    this.remarks,
    this.uploadedAt,
    this.verifiedAt,
    required this.createdAt,
  });

  factory AdminComplianceRow.fromJson(Map<String, dynamic> json) => AdminComplianceRow(
        id: json['id'],
        orderId: json['order_id'],
        orderNumber: json['order_number'],
        documentName: json['document_name'],
        responsibleRole: json['responsible_role'],
        mandatory: json['mandatory'] ?? true,
        status: json['status'],
        importerName: json['importer_name'] ?? '',
        exporterName: json['exporter_name'] ?? '',
        logisticsName: json['logistics_name'],
        originCountry: json['origin_country'],
        destinationCountry: json['destination_country'],
        uploadedFile: json['uploaded_file'],
        remarks: json['remarks'],
        uploadedAt: json['uploaded_at'] != null ? DateTime.parse(json['uploaded_at']) : null,
        verifiedAt: json['verified_at'] != null ? DateTime.parse(json['verified_at']) : null,
        createdAt: DateTime.parse(json['created_at']),
      );
}

class ComplianceSummary {
  final int pendingVerification;
  final int verified;
  final int rejected;
  final int blockedShipments;

  ComplianceSummary({required this.pendingVerification, required this.verified, required this.rejected, required this.blockedShipments});

  factory ComplianceSummary.fromJson(Map<String, dynamic> json) => ComplianceSummary(
        pendingVerification: json['pending_verification'] ?? 0,
        verified: json['verified'] ?? 0,
        rejected: json['rejected'] ?? 0,
        blockedShipments: json['blocked_shipments'] ?? 0,
      );
}

/// A rule engine row — GET /admin/compliance-rules. Any field being null means "applies
/// regardless of this dimension" (wildcard).
class ComplianceRule {
  final String id;
  final String? originCountry;
  final String? destinationCountry;
  final String? hsCode;
  final String? shippingMode;
  final String documentName;
  final String responsibleRole;
  final bool mandatory;
  final int displayOrder;
  final String? description;
  final DateTime createdAt;

  ComplianceRule({
    required this.id,
    this.originCountry,
    this.destinationCountry,
    this.hsCode,
    this.shippingMode,
    required this.documentName,
    required this.responsibleRole,
    required this.mandatory,
    required this.displayOrder,
    this.description,
    required this.createdAt,
  });

  factory ComplianceRule.fromJson(Map<String, dynamic> json) => ComplianceRule(
        id: json['id'],
        originCountry: json['origin_country'],
        destinationCountry: json['destination_country'],
        hsCode: json['hs_code'],
        shippingMode: json['shipping_mode'],
        documentName: json['document_name'],
        responsibleRole: json['responsible_role'],
        mandatory: json['mandatory'] ?? true,
        displayOrder: json['display_order'] ?? 0,
        description: json['description'],
        createdAt: DateTime.parse(json['created_at']),
      );
}
