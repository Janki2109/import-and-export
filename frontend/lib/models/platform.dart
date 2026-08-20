class Dispute {
  final String id;
  final String orderId;
  final String reason;
  final String status;
  final String? resolutionNotes;
  final DateTime createdAt;

  Dispute({
    required this.id,
    required this.orderId,
    required this.reason,
    required this.status,
    this.resolutionNotes,
    required this.createdAt,
  });

  factory Dispute.fromJson(Map<String, dynamic> json) => Dispute(
        id: json['id'],
        orderId: json['order_id'],
        reason: json['reason'],
        status: json['status'],
        resolutionNotes: json['resolution_notes'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class FleetVehicle {
  final String id;
  final String vehicleType;
  final String registrationNumber;
  final double? capacityKg;
  final double? capacityCbm;
  final String? serviceRoute;
  final String status;

  FleetVehicle({
    required this.id,
    required this.vehicleType,
    required this.registrationNumber,
    this.capacityKg,
    this.capacityCbm,
    this.serviceRoute,
    required this.status,
  });

  factory FleetVehicle.fromJson(Map<String, dynamic> json) => FleetVehicle(
        id: json['id'],
        vehicleType: json['vehicle_type'],
        registrationNumber: json['registration_number'],
        capacityKg: (json['capacity_kg'] as num?)?.toDouble(),
        capacityCbm: (json['capacity_cbm'] as num?)?.toDouble(),
        serviceRoute: json['service_route'],
        status: json['status'],
      );
}

class Product {
  final String id;
  final String name;
  final String? hsnCode;
  final String? description;
  final String unit;
  final double unitPrice;
  final double minOrderQty;
  final String? imageUrl;
  final bool isActive;

  Product({
    required this.id,
    required this.name,
    this.hsnCode,
    this.description,
    required this.unit,
    required this.unitPrice,
    required this.minOrderQty,
    this.imageUrl,
    required this.isActive,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'],
        name: json['name'],
        hsnCode: json['hsn_code'],
        description: json['description'],
        unit: json['unit'],
        unitPrice: (json['unit_price'] as num).toDouble(),
        minOrderQty: (json['min_order_qty'] as num).toDouble(),
        imageUrl: json['image_url'],
        isActive: json['is_active'] ?? true,
      );
}

class Membership {
  final String tier;
  final bool isFeatured;
  final DateTime? expiresAt;

  Membership({required this.tier, required this.isFeatured, this.expiresAt});

  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
        tier: json['tier'],
        isFeatured: json['is_featured'] ?? false,
        expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
      );
}

class LogisticsPartner {
  final String userId;
  final String fullName;
  final String? companyName;
  final String? city;
  final String? country;
  final bool kycVerified;
  final List<String> vehicleTypes;

  LogisticsPartner({
    required this.userId,
    required this.fullName,
    this.companyName,
    this.city,
    this.country,
    required this.kycVerified,
    required this.vehicleTypes,
  });

  factory LogisticsPartner.fromJson(Map<String, dynamic> json) => LogisticsPartner(
        userId: json['user_id'],
        fullName: json['full_name'],
        companyName: json['company_name'],
        city: json['city'],
        country: json['country'],
        kycVerified: json['kyc_verified'] ?? false,
        vehicleTypes: (json['vehicle_types'] as List?)?.cast<String>() ?? [],
      );
}

class Advertisement {
  final String id;
  final String advertiserId;
  final String? advertiserName;
  final String? advertiserRole;
  final String title;
  final String? description;
  final String? category;
  final String mediaType; // "image" | "video"
  final String imageUrl; // holds the video URL too when mediaType == "video"
  final double? price;
  final String? contactInfo;
  final int views;
  final String? targetUrl;
  final bool isActive;
  final DateTime createdAt;

  Advertisement({
    required this.id,
    required this.advertiserId,
    this.advertiserName,
    this.advertiserRole,
    required this.title,
    this.description,
    this.category,
    this.mediaType = 'image',
    required this.imageUrl,
    this.price,
    this.contactInfo,
    this.views = 0,
    this.targetUrl,
    this.isActive = true,
    required this.createdAt,
  });

  bool get isVideo => mediaType == 'video';

  factory Advertisement.fromJson(Map<String, dynamic> json) => Advertisement(
        id: json['id'],
        advertiserId: json['advertiser_id'] ?? '',
        advertiserName: json['advertiser_name'],
        advertiserRole: json['advertiser_role'],
        title: json['title'],
        description: json['description'],
        category: json['category'],
        mediaType: json['media_type'] ?? 'image',
        imageUrl: json['image_url'],
        price: (json['price'] as num?)?.toDouble(),
        contactInfo: json['contact_info'],
        views: (json['views'] as num?)?.toInt() ?? 0,
        targetUrl: json['target_url'],
        isActive: json['is_active'] ?? true,
        createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      );
}
