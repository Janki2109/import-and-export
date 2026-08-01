class Company {
  final String id;
  final String companyName;
  final String? businessType;
  final String? registrationNumber;
  final String? address;
  final String? city;
  final String? country;
  final String? website;
  final String? productsImported;
  final String? preferredShippingMode;

  Company({
    required this.id,
    required this.companyName,
    this.businessType,
    this.registrationNumber,
    this.address,
    this.city,
    this.country,
    this.website,
    this.productsImported,
    this.preferredShippingMode,
  });

  factory Company.fromJson(Map<String, dynamic> json) => Company(
        id: json['id'],
        companyName: json['company_name'],
        businessType: json['business_type'],
        registrationNumber: json['registration_number'],
        address: json['address'],
        city: json['city'],
        country: json['country'],
        website: json['website'],
        productsImported: json['products_imported'],
        preferredShippingMode: json['preferred_shipping_mode'],
      );
}
