class Company {
  final String id;
  final String userId;
  final String companyName;
  final String? businessType;
  final String? registrationNumber;
  final String? address;
  final String? city;
  final String? country;
  final String? website;
  final String? productsImported;
  final String? preferredShippingMode;
  final List<String> certifications;

  Company({
    required this.id,
    this.userId = '',
    required this.companyName,
    this.businessType,
    this.registrationNumber,
    this.address,
    this.city,
    this.country,
    this.website,
    this.productsImported,
    this.preferredShippingMode,
    this.certifications = const [],
  });

  factory Company.fromJson(Map<String, dynamic> json) => Company(
        id: json['id'],
        userId: json['user_id'] ?? '',
        companyName: json['company_name'],
        businessType: json['business_type'],
        registrationNumber: json['registration_number'],
        address: json['address'],
        city: json['city'],
        country: json['country'],
        website: json['website'],
        productsImported: json['products_imported'],
        preferredShippingMode: json['preferred_shipping_mode'],
        certifications: (json['certifications'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

/// A row in the importer-facing supplier directory (Journey 3) — trimmed for browsing/search.
class DirectoryListing {
  final String companyId;
  final String userId;
  final String companyName;
  final String? city;
  final String? country;
  final String? businessType;
  final double? avgRating;
  final int ratingCount;
  final int productCount;

  DirectoryListing({
    required this.companyId,
    required this.userId,
    required this.companyName,
    this.city,
    this.country,
    this.businessType,
    this.avgRating,
    required this.ratingCount,
    required this.productCount,
  });

  factory DirectoryListing.fromJson(Map<String, dynamic> json) => DirectoryListing(
        companyId: json['company_id'],
        userId: json['user_id'],
        companyName: json['company_name'],
        city: json['city'],
        country: json['country'],
        businessType: json['business_type'],
        avgRating: (json['avg_rating'] as num?)?.toDouble(),
        ratingCount: json['rating_count'] ?? 0,
        productCount: json['product_count'] ?? 0,
      );
}

class CompanyRating {
  final String id;
  final String companyId;
  final String orderId;
  final String ratedBy;
  final int score;
  final String? comment;
  final String createdAt;

  CompanyRating({
    required this.id,
    required this.companyId,
    required this.orderId,
    required this.ratedBy,
    required this.score,
    this.comment,
    required this.createdAt,
  });

  factory CompanyRating.fromJson(Map<String, dynamic> json) => CompanyRating(
        id: json['id'],
        companyId: json['company_id'],
        orderId: json['order_id'],
        ratedBy: json['rated_by'],
        score: json['score'],
        comment: json['comment'],
        createdAt: json['created_at'] ?? '',
      );
}

/// The full public profile behind "open company profile" (Journey 3).
class CompanyProfile {
  final Company company;
  final double? avgRating;
  final int ratingCount;
  final double? avgResponseTimeHours;
  final List<dynamic> productsJson;

  CompanyProfile({
    required this.company,
    this.avgRating,
    required this.ratingCount,
    this.avgResponseTimeHours,
    required this.productsJson,
  });

  factory CompanyProfile.fromJson(Map<String, dynamic> json) => CompanyProfile(
        company: Company.fromJson(json['company']),
        avgRating: (json['avg_rating'] as num?)?.toDouble(),
        ratingCount: json['rating_count'] ?? 0,
        avgResponseTimeHours: (json['avg_response_time_hours'] as num?)?.toDouble(),
        productsJson: json['products'] as List? ?? [],
      );
}
