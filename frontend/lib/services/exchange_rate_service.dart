import '../core/network/api_client.dart';

/// RFQ Pricing section's currency dropdown (INR/USD/EUR/AED) — converts the entered Target
/// Price live instead of just relabeling it. Backed by GET /search/exchange-rates (rates are
/// always FROM 1 INR); cached in-memory for the app session so repeated currency switches
/// don't re-hit the network every time.
class ExchangeRateService {
  final ApiClient _client = ApiClient();
  static Map<String, double>? _cachedRates;

  /// Rates FROM 1 INR to each currency, e.g. {"INR": 1, "USD": 0.012, ...}. Throws on
  /// failure — callers decide how to degrade gracefully (see create_rfq_screen.dart).
  Future<Map<String, double>> getRates({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedRates != null) return _cachedRates!;
    final res = await _client.get('/search/exchange-rates');
    final raw = res.data['data']['rates'] as Map<String, dynamic>;
    final rates = raw.map((k, v) => MapEntry(k, (v as num).toDouble()));
    _cachedRates = rates;
    return rates;
  }

  /// Converts [amount] from [fromCurrency] to [toCurrency], routing through INR as the
  /// anchor (the rate table's base) so any pair converts with a single, consistent table —
  /// never by chaining previously-displayed/rounded values, which is what avoids compounding
  /// drift across repeated conversions.
  double convert(double amount, String fromCurrency, String toCurrency, Map<String, double> rates) {
    if (fromCurrency == toCurrency) return amount;
    final fromRate = rates[fromCurrency];
    final toRate = rates[toCurrency];
    if (fromRate == null || fromRate == 0 || toRate == null) {
      throw StateError('Missing exchange rate for $fromCurrency or $toCurrency');
    }
    final amountInInr = amount / fromRate;
    return amountInInr * toRate;
  }
}
