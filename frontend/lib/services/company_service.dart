import '../core/network/api_client.dart';
import '../models/company.dart';

class CompanyService {
  final ApiClient _client = ApiClient();

  /// Returns null if the "Create Company" onboarding step hasn't been completed yet.
  Future<Company?> getMine() async {
    final res = await _client.get('/company/me');
    final data = res.data['data'];
    if (data == null) return null;
    return Company.fromJson(data);
  }

  Future<Company> upsert({
    required String companyName,
    String? businessType,
    String? registrationNumber,
    String? address,
    String? city,
    String? country,
    String? website,
    String? productsImported,
    String? preferredShippingMode,
  }) async {
    final res = await _client.post('/company', data: {
      'company_name': companyName,
      'business_type': businessType,
      'registration_number': registrationNumber,
      'address': address,
      'city': city,
      'country': country,
      'website': website,
      'products_imported': productsImported,
      'preferred_shipping_mode': preferredShippingMode,
    });
    return Company.fromJson(res.data['data']);
  }
}
