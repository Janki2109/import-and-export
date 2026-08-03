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
    List<String>? certifications,
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
      'certifications': certifications,
    });
    return Company.fromJson(res.data['data']);
  }

  /// Journey 3 — importer-facing supplier directory: browse/search exporter companies.
  Future<List<DirectoryListing>> listDirectory({String search = ''}) async {
    final res = await _client.get('/companies', query: {'search': search});
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => DirectoryListing.fromJson(e)).toList();
  }

  /// Journey 3 — open a company profile: details, certifications, products, ratings,
  /// average response time, all in one call.
  Future<CompanyProfile> getProfile(String companyId) async {
    final res = await _client.get('/companies/$companyId');
    return CompanyProfile.fromJson(res.data['data']);
  }

  Future<List<CompanyRating>> listRatings(String companyId) async {
    final res = await _client.get('/companies/$companyId/ratings');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => CompanyRating.fromJson(e)).toList();
  }

  Future<void> rateCompany(String companyId, {required String orderId, required int score, String? comment}) async {
    await _client.post('/companies/$companyId/ratings', data: {
      'order_id': orderId,
      'score': score,
      'comment': comment,
    });
  }
}
