class AdminUser {
  final String id;
  final String role;
  final String fullName;
  final String email;
  final String phone;
  final bool isActive;

  AdminUser({required this.id, required this.role, required this.fullName, required this.email, required this.phone, required this.isActive});

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'],
        role: json['role'],
        fullName: json['full_name'],
        email: json['email'],
        phone: json['phone'],
        isActive: json['is_active'] ?? true,
      );
}

/// User Management row — base user fields plus company/country and GST/IEC/KYC
/// verification, already joined server-side (GET /admin/users/rich).
class AdminUserRow {
  final String id;
  final String role;
  final String fullName;
  final String? companyName;
  final String email;
  final String phone;
  final String? avatarUrl;
  final bool isActive;
  final DateTime createdAt;
  final String? country;
  final String? gstNumber;
  final String? iecCode;
  final String? kycStatus;

  AdminUserRow({
    required this.id,
    required this.role,
    required this.fullName,
    this.companyName,
    required this.email,
    required this.phone,
    this.avatarUrl,
    required this.isActive,
    required this.createdAt,
    this.country,
    this.gstNumber,
    this.iecCode,
    this.kycStatus,
  });

  factory AdminUserRow.fromJson(Map<String, dynamic> json) => AdminUserRow(
        id: json['id'],
        role: json['role'],
        fullName: json['full_name'],
        companyName: json['company_name'],
        email: json['email'],
        phone: json['phone'],
        avatarUrl: json['avatar_url'],
        isActive: json['is_active'] ?? true,
        createdAt: DateTime.parse(json['created_at']),
        country: json['country'],
        gstNumber: json['gst_number'],
        iecCode: json['iec_code'],
        kycStatus: json['kyc_status'],
      );
}

/// Order Management row — order fields plus importer/exporter/logistics names and
/// escrow/shipment status, already joined server-side (GET /admin/orders/rich).
class AdminOrderRow {
  final String id;
  final String orderNumber;
  final String importerId;
  final String importerName;
  final String exporterId;
  final String exporterName;
  final String? logisticsName;
  final String productName;
  final double totalAmount;
  final double platformFeeAmount;
  final double exporterPayoutAmount;
  final String status;
  final String? escrowStatus;
  final String? shipmentStatus;
  final DateTime createdAt;

  AdminOrderRow({
    required this.id,
    required this.orderNumber,
    required this.importerId,
    required this.importerName,
    required this.exporterId,
    required this.exporterName,
    this.logisticsName,
    required this.productName,
    required this.totalAmount,
    required this.platformFeeAmount,
    required this.exporterPayoutAmount,
    required this.status,
    this.escrowStatus,
    this.shipmentStatus,
    required this.createdAt,
  });

  factory AdminOrderRow.fromJson(Map<String, dynamic> json) => AdminOrderRow(
        id: json['id'],
        orderNumber: json['order_number'],
        importerId: json['importer_id'],
        importerName: json['importer_name'] ?? '',
        exporterId: json['exporter_id'],
        exporterName: json['exporter_name'] ?? '',
        logisticsName: json['logistics_name'],
        productName: json['product_name'],
        totalAmount: (json['total_amount'] as num).toDouble(),
        platformFeeAmount: (json['platform_fee_amount'] as num?)?.toDouble() ?? 0,
        exporterPayoutAmount: (json['exporter_payout_amount'] as num?)?.toDouble() ?? 0,
        status: json['status'],
        escrowStatus: json['escrow_status'],
        shipmentStatus: json['shipment_status'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// Quotation Management row — quotation fields plus product/importer/exporter names,
/// already joined server-side (GET /admin/quotations).
class AdminQuotationRow {
  final String id;
  final String rfqId;
  final String exporterId;
  final String exporterName;
  final String importerName;
  final String productName;
  final double unitPrice;
  final double quantity;
  final double totalAmount;
  final String status;
  final DateTime validityDate;
  final DateTime createdAt;

  AdminQuotationRow({
    required this.id,
    required this.rfqId,
    required this.exporterId,
    required this.exporterName,
    required this.importerName,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.totalAmount,
    required this.status,
    required this.validityDate,
    required this.createdAt,
  });

  factory AdminQuotationRow.fromJson(Map<String, dynamic> json) => AdminQuotationRow(
        id: json['id'],
        rfqId: json['rfq_id'],
        exporterId: json['exporter_id'],
        exporterName: json['exporter_name'] ?? '',
        importerName: json['importer_name'] ?? '',
        productName: json['product_name'] ?? '',
        unitPrice: (json['unit_price'] as num).toDouble(),
        quantity: (json['quantity'] as num).toDouble(),
        totalAmount: (json['total_amount'] as num).toDouble(),
        status: json['status'],
        validityDate: DateTime.parse(json['validity_date']),
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// One user's wallet at a glance — GET /admin/wallets.
class AdminWalletRow {
  final String userId;
  final String fullName;
  final String role;
  final double balance;
  final double pendingRelease;
  final double totalReleased;
  final double totalWithdrawn;

  AdminWalletRow({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.balance,
    required this.pendingRelease,
    required this.totalReleased,
    required this.totalWithdrawn,
  });

  factory AdminWalletRow.fromJson(Map<String, dynamic> json) => AdminWalletRow(
        userId: json['user_id'],
        fullName: json['full_name'],
        role: json['role'],
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        pendingRelease: (json['pending_release'] as num?)?.toDouble() ?? 0,
        totalReleased: (json['total_released'] as num?)?.toDouble() ?? 0,
        totalWithdrawn: (json['total_withdrawn'] as num?)?.toDouble() ?? 0,
      );
}

/// A withdrawal request — GET /admin/withdrawals. Status is 'pending' | 'paid' | 'rejected',
/// derived server-side from the ledger entry's reference_id marker.
class AdminWithdrawalRow {
  final String id;
  final String userId;
  final String userName;
  final String role;
  final double amount;
  final String? referenceId;
  final String status;
  final DateTime createdAt;

  AdminWithdrawalRow({
    required this.id,
    required this.userId,
    required this.userName,
    required this.role,
    required this.amount,
    this.referenceId,
    required this.status,
    required this.createdAt,
  });

  factory AdminWithdrawalRow.fromJson(Map<String, dynamic> json) => AdminWithdrawalRow(
        id: json['id'],
        userId: json['user_id'],
        userName: json['user_name'],
        role: json['role'],
        amount: (json['amount'] as num).toDouble(),
        referenceId: json['reference_id'],
        status: json['status'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class Analytics {
  final int totalUsers;
  final int totalImporters;
  final int totalExporters;
  final int totalLogistics;
  final int totalOrders;
  final double totalGMV;
  final double totalPlatformFees;
  final Map<String, dynamic> ordersByStatus;
  final int pendingKYCCount;
  final int openDisputesCount;

  Analytics({
    required this.totalUsers,
    required this.totalImporters,
    required this.totalExporters,
    required this.totalLogistics,
    required this.totalOrders,
    required this.totalGMV,
    required this.totalPlatformFees,
    required this.ordersByStatus,
    required this.pendingKYCCount,
    required this.openDisputesCount,
  });

  factory Analytics.fromJson(Map<String, dynamic> json) => Analytics(
        totalUsers: json['total_users'] ?? 0,
        totalImporters: json['total_importers'] ?? 0,
        totalExporters: json['total_exporters'] ?? 0,
        totalLogistics: json['total_logistics'] ?? 0,
        totalOrders: json['total_orders'] ?? 0,
        totalGMV: (json['total_gmv'] as num?)?.toDouble() ?? 0,
        totalPlatformFees: (json['total_platform_fees'] as num?)?.toDouble() ?? 0,
        ordersByStatus: (json['orders_by_status'] as Map?)?.cast<String, dynamic>() ?? {},
        pendingKYCCount: json['pending_kyc_count'] ?? 0,
        openDisputesCount: json['open_disputes_count'] ?? 0,
      );
}

class FraudSignal {
  final String type;
  final String? userId;
  final String? email;
  final String description;
  final String severity;

  FraudSignal({required this.type, this.userId, this.email, required this.description, required this.severity});

  factory FraudSignal.fromJson(Map<String, dynamic> json) => FraudSignal(
        type: json['type'],
        userId: json['user_id'],
        email: json['email'],
        description: json['description'],
        severity: json['severity'],
      );
}

/// Journey 12 — a persisted security flag from the fraud sweep, reviewable/resolvable over
/// time (unlike FraudSignal, which is recomputed fresh on every request and never stored).
class SecurityFlag {
  final String id;
  final String? userId;
  final String rule;
  final String severity;
  final String description;
  final bool resolved;
  final DateTime createdAt;

  SecurityFlag({
    required this.id,
    this.userId,
    required this.rule,
    required this.severity,
    required this.description,
    required this.resolved,
    required this.createdAt,
  });

  factory SecurityFlag.fromJson(Map<String, dynamic> json) => SecurityFlag(
        id: json['id'],
        userId: json['user_id'],
        rule: json['rule'],
        severity: json['severity'],
        description: json['description'],
        resolved: json['resolved'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// One row in the admin "Escrow Payments" list — order + escrow status + both parties'
/// names, already joined server-side.
class EscrowOrderRow {
  final String orderId;
  final String orderNumber;
  final String importerId;
  final String importerName;
  final String exporterId;
  final String exporterName;
  final double orderAmount;
  final double payoutAmount;
  final String orderStatus;
  final String escrowStatus;
  final bool hasOpenDispute;
  final DateTime? releaseDueAt;
  final DateTime? heldAt;
  final DateTime? releasedAt;
  final DateTime? refundedAt;

  EscrowOrderRow({
    required this.orderId,
    required this.orderNumber,
    required this.importerId,
    required this.importerName,
    required this.exporterId,
    required this.exporterName,
    required this.orderAmount,
    required this.payoutAmount,
    required this.orderStatus,
    required this.escrowStatus,
    this.hasOpenDispute = false,
    this.releaseDueAt,
    this.heldAt,
    this.releasedAt,
    this.refundedAt,
  });

  factory EscrowOrderRow.fromJson(Map<String, dynamic> json) => EscrowOrderRow(
        orderId: json['order_id'],
        orderNumber: json['order_number'],
        importerId: json['importer_id'],
        importerName: json['importer_name'],
        exporterId: json['exporter_id'],
        exporterName: json['exporter_name'],
        orderAmount: (json['order_amount'] as num).toDouble(),
        payoutAmount: (json['payout_amount'] as num).toDouble(),
        orderStatus: json['order_status'],
        escrowStatus: json['escrow_status'],
        hasOpenDispute: json['has_open_dispute'] ?? false,
        releaseDueAt: json['release_due_at'] != null ? DateTime.parse(json['release_due_at']) : null,
        heldAt: json['held_at'] != null ? DateTime.parse(json['held_at']) : null,
        releasedAt: json['released_at'] != null ? DateTime.parse(json['released_at']) : null,
        refundedAt: json['refunded_at'] != null ? DateTime.parse(json['refunded_at']) : null,
      );
}

class EscrowSummary {
  final double holdingBalance;
  final double pendingRelease;
  final double totalReleased;
  final double totalRefunded;

  EscrowSummary({required this.holdingBalance, required this.pendingRelease, required this.totalReleased, required this.totalRefunded});

  factory EscrowSummary.fromJson(Map<String, dynamic> json) => EscrowSummary(
        holdingBalance: (json['holding_balance'] as num?)?.toDouble() ?? 0,
        pendingRelease: (json['pending_release'] as num?)?.toDouble() ?? 0,
        totalReleased: (json['total_released'] as num?)?.toDouble() ?? 0,
        totalRefunded: (json['total_refunded'] as num?)?.toDouble() ?? 0,
      );
}

/// One point in a monthly trend chart — count and/or a monetary value for that month.
class MonthPoint {
  final String month;
  final int count;
  final double value;
  MonthPoint({required this.month, required this.count, required this.value});

  factory MonthPoint.fromJson(Map<String, dynamic> json) => MonthPoint(
        month: json['month'] ?? '',
        count: json['count'] ?? 0,
        value: (json['value'] as num?)?.toDouble() ?? 0,
      );
}

/// A labelled count — used for country-wise trade and top export category bars.
class NamedCount {
  final String label;
  final int count;
  NamedCount({required this.label, required this.count});

  factory NamedCount.fromJson(Map<String, dynamic> json) => NamedCount(
        label: json['label'] ?? '',
        count: json['count'] ?? 0,
      );
}

/// Chart data for the admin dashboard — GET /admin/analytics/charts.
class ChartAnalytics {
  final List<MonthPoint> monthlyOrders;
  final List<MonthPoint> monthlyRevenue;
  final List<NamedCount> countryTrade;
  final List<MonthPoint> rfqTrend;
  final List<NamedCount> topExportCategories;
  final int openRfqCount;
  final int activeShipmentCount;
  final int walletTxnCount;

  ChartAnalytics({
    required this.monthlyOrders,
    required this.monthlyRevenue,
    required this.countryTrade,
    required this.rfqTrend,
    required this.topExportCategories,
    required this.openRfqCount,
    required this.activeShipmentCount,
    required this.walletTxnCount,
  });

  factory ChartAnalytics.fromJson(Map<String, dynamic> json) => ChartAnalytics(
        monthlyOrders: ((json['monthly_orders'] as List?) ?? []).map((e) => MonthPoint.fromJson(e)).toList(),
        monthlyRevenue: ((json['monthly_revenue'] as List?) ?? []).map((e) => MonthPoint.fromJson(e)).toList(),
        countryTrade: ((json['country_trade'] as List?) ?? []).map((e) => NamedCount.fromJson(e)).toList(),
        rfqTrend: ((json['rfq_trend'] as List?) ?? []).map((e) => MonthPoint.fromJson(e)).toList(),
        topExportCategories: ((json['top_export_categories'] as List?) ?? []).map((e) => NamedCount.fromJson(e)).toList(),
        openRfqCount: json['open_rfq_count'] ?? 0,
        activeShipmentCount: json['active_shipment_count'] ?? 0,
        walletTxnCount: json['wallet_txn_count'] ?? 0,
      );
}

/// One RFQ row in the admin RFQ Management table — RFQ fields + the importer's name,
/// already joined server-side (GET /admin/rfqs).
class AdminRFQRow {
  final String id;
  final String rfqNumber;
  final String importerId;
  final String importerName;
  final String productName;
  final String? hsnCode;
  final double quantity;
  final String unit;
  final double? targetPrice;
  final String destinationCountry;
  final String? description;
  final String status;
  final DateTime createdAt;

  AdminRFQRow({
    required this.id,
    required this.rfqNumber,
    required this.importerId,
    required this.importerName,
    required this.productName,
    this.hsnCode,
    required this.quantity,
    required this.unit,
    this.targetPrice,
    required this.destinationCountry,
    this.description,
    required this.status,
    required this.createdAt,
  });

  factory AdminRFQRow.fromJson(Map<String, dynamic> json) => AdminRFQRow(
        id: json['id'],
        rfqNumber: json['rfq_number'],
        importerId: json['importer_id'],
        importerName: json['importer_name'] ?? '',
        productName: json['product_name'],
        hsnCode: json['hsn_code'],
        quantity: (json['quantity'] as num).toDouble(),
        unit: json['unit'],
        targetPrice: (json['target_price'] as num?)?.toDouble(),
        destinationCountry: json['destination_country'],
        description: json['description'],
        status: json['status'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// One shipment row in the admin Shipment Management table — Shipment fields + order/party
/// names, already joined server-side (GET /admin/shipments).
class AdminShipmentRow {
  final String id;
  final String orderId;
  final String orderNumber;
  final String importerName;
  final String exporterName;
  final String? logisticsName;
  final String? trackingNumber;
  final String status;
  final String? carrierName;
  final String? pickupAddress;
  final String? deliveryAddress;
  final DateTime? estimatedDelivery;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;

  AdminShipmentRow({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.importerName,
    required this.exporterName,
    this.logisticsName,
    this.trackingNumber,
    required this.status,
    this.carrierName,
    this.pickupAddress,
    this.deliveryAddress,
    this.estimatedDelivery,
    this.pickedUpAt,
    this.deliveredAt,
    required this.createdAt,
  });

  factory AdminShipmentRow.fromJson(Map<String, dynamic> json) => AdminShipmentRow(
        id: json['id'],
        orderId: json['order_id'],
        orderNumber: json['order_number'],
        importerName: json['importer_name'] ?? '',
        exporterName: json['exporter_name'] ?? '',
        logisticsName: json['logistics_name'],
        trackingNumber: json['tracking_number'],
        status: json['status'],
        carrierName: json['carrier_name'],
        pickupAddress: json['pickup_address'],
        deliveryAddress: json['delivery_address'],
        estimatedDelivery: json['estimated_delivery'] != null ? DateTime.parse(json['estimated_delivery']) : null,
        pickedUpAt: json['picked_up_at'] != null ? DateTime.parse(json['picked_up_at']) : null,
        deliveredAt: json['delivered_at'] != null ? DateTime.parse(json['delivered_at']) : null,
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// Platform Settings — GET /admin/settings. smtpPassword is never returned by the backend;
/// hasSmtpPassword just tells the UI whether one is already configured.
class PlatformSettings {
  final String appName;
  final String? logoUrl;
  final String? supportEmail;
  final String currency;
  final String? smtpHost;
  final int? smtpPort;
  final String? smtpUsername;
  final String? smtpFrom;
  final bool hasSmtpPassword;
  final DateTime updatedAt;

  PlatformSettings({
    required this.appName,
    this.logoUrl,
    this.supportEmail,
    required this.currency,
    this.smtpHost,
    this.smtpPort,
    this.smtpUsername,
    this.smtpFrom,
    required this.hasSmtpPassword,
    required this.updatedAt,
  });

  factory PlatformSettings.fromJson(Map<String, dynamic> json) => PlatformSettings(
        appName: json['app_name'] ?? '',
        logoUrl: json['logo_url'],
        supportEmail: json['support_email'],
        currency: json['currency'] ?? 'INR',
        smtpHost: json['smtp_host'],
        smtpPort: json['smtp_port'],
        smtpUsername: json['smtp_username'],
        smtpFrom: json['smtp_from'],
        hasSmtpPassword: json['has_smtp_password'] ?? false,
        updatedAt: DateTime.parse(json['updated_at']),
      );
}

/// Logistics Management row — GET /admin/logistics. No rating field: nothing in the
/// schema collects one yet, so it's simply not shown rather than fabricated.
class AdminLogisticsRow {
  final String userId;
  final String fullName;
  final String? companyName;
  final String email;
  final String phone;
  final String? country;
  final bool isActive;
  final int fleetCount;
  final String? vehicleTypes;
  final int ordersAssigned;
  final DateTime createdAt;

  AdminLogisticsRow({
    required this.userId,
    required this.fullName,
    this.companyName,
    required this.email,
    required this.phone,
    this.country,
    required this.isActive,
    required this.fleetCount,
    this.vehicleTypes,
    required this.ordersAssigned,
    required this.createdAt,
  });

  factory AdminLogisticsRow.fromJson(Map<String, dynamic> json) => AdminLogisticsRow(
        userId: json['user_id'],
        fullName: json['full_name'],
        companyName: json['company_name'],
        email: json['email'],
        phone: json['phone'],
        country: json['country'],
        isActive: json['is_active'] ?? true,
        fleetCount: json['fleet_count'] ?? 0,
        vehicleTypes: json['vehicle_types'],
        ordersAssigned: json['orders_assigned'] ?? 0,
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// Chat Management row — GET /admin/chats.
class AdminConversationRow {
  final String id;
  final String userAId;
  final String userAName;
  final String userARole;
  final String? userAEmail;
  final String userBId;
  final String userBName;
  final String userBRole;
  final String? userBEmail;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int messageCount;
  final bool isArchived;
  final DateTime createdAt;

  AdminConversationRow({
    required this.id,
    required this.userAId,
    required this.userAName,
    required this.userARole,
    this.userAEmail,
    required this.userBId,
    required this.userBName,
    required this.userBRole,
    this.userBEmail,
    this.lastMessagePreview,
    this.lastMessageAt,
    required this.messageCount,
    required this.isArchived,
    required this.createdAt,
  });

  factory AdminConversationRow.fromJson(Map<String, dynamic> json) => AdminConversationRow(
        id: json['id'],
        userAId: json['user_a_id'],
        userAName: json['user_a_name'],
        userARole: json['user_a_role'],
        userAEmail: json['user_a_email'],
        userBId: json['user_b_id'],
        userBName: json['user_b_name'],
        userBRole: json['user_b_role'],
        userBEmail: json['user_b_email'],
        lastMessagePreview: json['last_message_preview'],
        lastMessageAt: json['last_message_at'] != null ? DateTime.parse(json['last_message_at']) : null,
        messageCount: json['message_count'] ?? 0,
        isArchived: json['is_archived'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// One Global Search hit — GET /admin/search?q=.
class AdminSearchResult {
  final String category;
  final String id;
  final String title;
  final String subtitle;

  AdminSearchResult({required this.category, required this.id, required this.title, required this.subtitle});

  factory AdminSearchResult.fromJson(Map<String, dynamic> json) => AdminSearchResult(
        category: json['category'],
        id: json['id'],
        title: json['title'],
        subtitle: json['subtitle'],
      );
}
