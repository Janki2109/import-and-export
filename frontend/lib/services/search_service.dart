import '../core/network/api_client.dart';
import '../models/reference.dart';

/// HS Code / GST / Country / Policy search plus Duty/Freight/Landed-Cost calculators
/// and AI-assisted product-to-HS-code search.
class SearchService {
  final ApiClient _client = ApiClient();

  Future<List<HSCode>> searchHSCodes(String query) async {
    final res = await _client.get('/search/hs-codes', query: {'q': query});
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => HSCode.fromJson(e)).toList();
  }

  Future<List<GSTRate>> listGSTRates() async {
    final res = await _client.get('/search/gst-rates');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => GSTRate.fromJson(e)).toList();
  }

  Future<List<Country>> searchCountries(String query) async {
    final res = await _client.get('/search/countries', query: {'q': query});
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => Country.fromJson(e)).toList();
  }

  Future<List<TradePolicy>> listPolicies({String? countryId, String? policyType}) async {
    final res = await _client.get('/search/policies', query: {
      if (countryId != null) 'country_id': countryId,
      if (policyType != null) 'policy_type': policyType,
    });
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => TradePolicy.fromJson(e)).toList();
  }

  Future<List<AIProductMatch>> aiProductSearch(String query) async {
    final res = await _client.get('/search/ai-product-search', query: {'q': query});
    final list = res.data['data']['matches'] as List? ?? [];
    return list.map((e) => AIProductMatch.fromJson(e)).toList();
  }

  Future<DutyBreakdown> calculateDuty({required String hsCode, required double assessableValue}) async {
    final res = await _client.get('/calculators/duty', query: {
      'hs_code': hsCode,
      'assessable_value': assessableValue.toString(),
    });
    return DutyBreakdown.fromJson(res.data['data']);
  }

  Future<FreightEstimate> calculateFreight({
    required String mode,
    required double weightKg,
    double lengthCm = 0,
    double widthCm = 0,
    double heightCm = 0,
  }) async {
    final res = await _client.get('/calculators/freight', query: {
      'mode': mode,
      'weight_kg': weightKg.toString(),
      'length_cm': lengthCm.toString(),
      'width_cm': widthCm.toString(),
      'height_cm': heightCm.toString(),
    });
    return FreightEstimate.fromJson(res.data['data']);
  }

  Future<LandedCostBreakdown> calculateLandedCost({
    required String hsCode,
    required double fobValue,
    double freight = 0,
    double insurance = 0,
    double otherCharges = 0,
  }) async {
    final res = await _client.post('/calculators/landed-cost', data: {
      'hs_code': hsCode,
      'fob_value': fobValue,
      'freight': freight,
      'insurance': insurance,
      'other_charges': otherCharges,
    });
    return LandedCostBreakdown.fromJson(res.data['data']);
  }
}
