class RFQ {
  final String id;
  final String rfqNumber;
  final String importerId;
  final String productName;
  final String? hsnCode;
  final double quantity;
  final String unit;
  final double? targetPrice;
  final String destinationCountry;
  final String? description;
  final String status;
  final DateTime createdAt;

  RFQ({
    required this.id,
    required this.rfqNumber,
    required this.importerId,
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

  factory RFQ.fromJson(Map<String, dynamic> json) => RFQ(
        id: json['id'],
        rfqNumber: json['rfq_number'],
        importerId: json['importer_id'],
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

class Quotation {
  final String id;
  final String rfqId;
  final String exporterId;
  final double unitPrice;
  final double quantity;
  final double totalAmount;
  final DateTime validityDate;
  final String? terms;
  final String status;
  final String? orderId;
  final DateTime createdAt;

  Quotation({
    required this.id,
    required this.rfqId,
    required this.exporterId,
    required this.unitPrice,
    required this.quantity,
    required this.totalAmount,
    required this.validityDate,
    this.terms,
    required this.status,
    this.orderId,
    required this.createdAt,
  });

  factory Quotation.fromJson(Map<String, dynamic> json) => Quotation(
        id: json['id'],
        rfqId: json['rfq_id'],
        exporterId: json['exporter_id'],
        unitPrice: (json['unit_price'] as num).toDouble(),
        quantity: (json['quantity'] as num).toDouble(),
        totalAmount: (json['total_amount'] as num).toDouble(),
        validityDate: DateTime.parse(json['validity_date']),
        terms: json['terms'],
        status: json['status'],
        orderId: json['order_id'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class LedgerEntry {
  final String id;
  final String? orderId;
  final String entryType;
  final double amount;
  final double? balanceAfter;
  final String description;
  final String? referenceId;
  final DateTime createdAt;

  LedgerEntry({
    required this.id,
    this.orderId,
    required this.entryType,
    required this.amount,
    this.balanceAfter,
    required this.description,
    this.referenceId,
    required this.createdAt,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        id: json['id'],
        orderId: json['order_id'],
        entryType: json['entry_type'],
        amount: (json['amount'] as num).toDouble(),
        balanceAfter: (json['balance_after'] as num?)?.toDouble(),
        description: json['description'],
        referenceId: json['reference_id'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class WalletSummary {
  final double balance;
  final double pendingRelease; // escrow held on this user's orders, not yet released
  final double totalReleased; // lifetime escrow payouts released to this user
  final List<LedgerEntry> transactions;

  WalletSummary({required this.balance, this.pendingRelease = 0, this.totalReleased = 0, required this.transactions});

  factory WalletSummary.fromJson(Map<String, dynamic> json) => WalletSummary(
        balance: (json['balance'] as num).toDouble(),
        pendingRelease: (json['pending_release'] as num?)?.toDouble() ?? 0,
        totalReleased: (json['total_released'] as num?)?.toDouble() ?? 0,
        transactions: ((json['transactions'] as List?) ?? [])
            .map((e) => LedgerEntry.fromJson(e))
            .toList(),
      );
}

class TradeDocument {
  final String id;
  final String orderId;
  final String type;
  final String fileUrl;
  final int version;
  final String? checksum;
  final String? signature;
  final DateTime createdAt;

  TradeDocument({
    required this.id,
    required this.orderId,
    required this.type,
    required this.fileUrl,
    required this.version,
    this.checksum,
    this.signature,
    required this.createdAt,
  });

  factory TradeDocument.fromJson(Map<String, dynamic> json) => TradeDocument(
        id: json['id'],
        orderId: json['order_id'],
        type: json['type'],
        fileUrl: json['file_url'],
        version: json['version'] ?? 1,
        checksum: json['checksum'],
        signature: json['signature'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

/// Journey 9 — one entry in a document's version history.
class TradeDocumentVersion {
  final String id;
  final String documentId;
  final int version;
  final String fileUrl;
  final String checksum;
  final String signature;
  final DateTime createdAt;

  TradeDocumentVersion({
    required this.id,
    required this.documentId,
    required this.version,
    required this.fileUrl,
    required this.checksum,
    required this.signature,
    required this.createdAt,
  });

  factory TradeDocumentVersion.fromJson(Map<String, dynamic> json) => TradeDocumentVersion(
        id: json['id'],
        documentId: json['document_id'],
        version: json['version'],
        fileUrl: json['file_url'],
        checksum: json['checksum'],
        signature: json['signature'],
        createdAt: DateTime.parse(json['created_at']),
      );
}
