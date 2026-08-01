/// Payment Terms & Milestone Escrow Engine — additive module models.
class PaymentTerms {
  final String id;
  final String orderId;
  final String paymentModel; // advance_100 | advance_balance | milestone_escrow | letter_of_credit | open_account | custom
  final String currency;
  final double totalAmount;
  final String? lcNumber;
  final String? lcBankName;
  final DateTime? lcExpiryDate;
  final String? lcStatus; // issued | pending | verified | completed
  final int? openAccountDays;
  final String status; // active | completed
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  PaymentTerms({
    required this.id,
    required this.orderId,
    required this.paymentModel,
    required this.currency,
    required this.totalAmount,
    this.lcNumber,
    this.lcBankName,
    this.lcExpiryDate,
    this.lcStatus,
    this.openAccountDays,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymentTerms.fromJson(Map<String, dynamic> json) => PaymentTerms(
        id: json['id'],
        orderId: json['order_id'],
        paymentModel: json['payment_model'],
        currency: json['currency'] ?? 'INR',
        totalAmount: (json['total_amount'] as num).toDouble(),
        lcNumber: json['lc_number'],
        lcBankName: json['lc_bank_name'],
        lcExpiryDate: json['lc_expiry_date'] != null ? DateTime.parse(json['lc_expiry_date']) : null,
        lcStatus: json['lc_status'],
        openAccountDays: json['open_account_days'],
        status: json['status'],
        createdBy: json['created_by'],
        createdAt: DateTime.parse(json['created_at']),
        updatedAt: DateTime.parse(json['updated_at']),
      );
}

class PaymentMilestone {
  final String id;
  final String paymentTermId;
  final int releaseOrder;
  final String title;
  final double percentage;
  final double amount;
  final String status; // pending | paid | waiting_approval | approved | released | rejected | on_hold
  final String triggerEvent;
  final bool proofRequired;
  final String? proofUrl;
  final DateTime? proofUploadedAt;
  final String? uploadedBy;
  final DateTime? paidAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? remarks;
  final DateTime? releasedAt;
  final DateTime createdAt;

  PaymentMilestone({
    required this.id,
    required this.paymentTermId,
    required this.releaseOrder,
    required this.title,
    required this.percentage,
    required this.amount,
    required this.status,
    required this.triggerEvent,
    required this.proofRequired,
    this.proofUrl,
    this.proofUploadedAt,
    this.uploadedBy,
    this.paidAt,
    this.reviewedBy,
    this.reviewedAt,
    this.remarks,
    this.releasedAt,
    required this.createdAt,
  });

  factory PaymentMilestone.fromJson(Map<String, dynamic> json) => PaymentMilestone(
        id: json['id'],
        paymentTermId: json['payment_term_id'],
        releaseOrder: json['release_order'],
        title: json['title'],
        percentage: (json['percentage'] as num).toDouble(),
        amount: (json['amount'] as num).toDouble(),
        status: json['status'],
        triggerEvent: json['trigger_event'] ?? 'manual_release',
        proofRequired: json['proof_required'] ?? false,
        proofUrl: json['proof_url'],
        proofUploadedAt: json['proof_uploaded_at'] != null ? DateTime.parse(json['proof_uploaded_at']) : null,
        uploadedBy: json['uploaded_by'],
        paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at']) : null,
        reviewedBy: json['reviewed_by'],
        reviewedAt: json['reviewed_at'] != null ? DateTime.parse(json['reviewed_at']) : null,
        remarks: json['remarks'],
        releasedAt: json['released_at'] != null ? DateTime.parse(json['released_at']) : null,
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// Admin payment management list row — GET /admin/payment-terms.
class AdminPaymentRow {
  final String id;
  final String orderId;
  final String paymentModel;
  final String currency;
  final double totalAmount;
  final String status;
  final DateTime createdAt;
  final String orderNumber;
  final String importerName;
  final String exporterName;
  final String productName;
  final int milestoneCount;
  final int releasedCount;

  AdminPaymentRow({
    required this.id,
    required this.orderId,
    required this.paymentModel,
    required this.currency,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    required this.orderNumber,
    required this.importerName,
    required this.exporterName,
    required this.productName,
    required this.milestoneCount,
    required this.releasedCount,
  });

  factory AdminPaymentRow.fromJson(Map<String, dynamic> json) => AdminPaymentRow(
        id: json['ID'] ?? json['id'],
        orderId: json['OrderID'] ?? json['order_id'],
        paymentModel: json['PaymentModel'] ?? json['payment_model'],
        currency: json['Currency'] ?? json['currency'] ?? 'INR',
        totalAmount: ((json['TotalAmount'] ?? json['total_amount']) as num).toDouble(),
        status: json['Status'] ?? json['status'],
        createdAt: DateTime.parse(json['CreatedAt'] ?? json['created_at']),
        orderNumber: json['OrderNumber'] ?? json['order_number'] ?? '',
        importerName: json['ImporterName'] ?? json['importer_name'] ?? '',
        exporterName: json['ExporterName'] ?? json['exporter_name'] ?? '',
        productName: json['ProductName'] ?? json['product_name'] ?? '',
        milestoneCount: json['MilestoneCount'] ?? json['milestone_count'] ?? 0,
        releasedCount: json['ReleasedCount'] ?? json['released_count'] ?? 0,
      );
}

class AdminPaymentSummary {
  final double totalEscrow;
  final int pendingReleases;
  final double released;
  final int upcomingMilestones;
  final int delayedMilestones;

  AdminPaymentSummary({
    required this.totalEscrow,
    required this.pendingReleases,
    required this.released,
    required this.upcomingMilestones,
    required this.delayedMilestones,
  });

  factory AdminPaymentSummary.fromJson(Map<String, dynamic> json) => AdminPaymentSummary(
        totalEscrow: ((json['TotalEscrow'] ?? json['total_escrow']) as num?)?.toDouble() ?? 0,
        pendingReleases: json['PendingReleases'] ?? json['pending_releases'] ?? 0,
        released: ((json['Released'] ?? json['released']) as num?)?.toDouble() ?? 0,
        upcomingMilestones: json['UpcomingMilestones'] ?? json['upcoming_milestones'] ?? 0,
        delayedMilestones: json['DelayedMilestones'] ?? json['delayed_milestones'] ?? 0,
      );
}
