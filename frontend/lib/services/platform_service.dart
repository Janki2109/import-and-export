import '../core/network/api_client.dart';
import '../models/platform.dart';

class DisputeService {
  final ApiClient _client = ApiClient();

  Future<Dispute> raise({required String orderId, required String reason}) async {
    final res = await _client.post('/disputes', data: {'order_id': orderId, 'reason': reason});
    return Dispute.fromJson(res.data['data']);
  }

  Future<List<Dispute>> listMine() async {
    final res = await _client.get('/disputes/mine');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => Dispute.fromJson(e)).toList();
  }
}

class FleetService {
  final ApiClient _client = ApiClient();

  Future<List<FleetVehicle>> listMine() async {
    final res = await _client.get('/fleet/mine');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => FleetVehicle.fromJson(e)).toList();
  }

  Future<void> create({
    required String vehicleType,
    required String registrationNumber,
    double? capacityKg,
    double? capacityCbm,
    String? serviceRoute,
  }) async {
    await _client.post('/fleet', data: {
      'vehicle_type': vehicleType,
      'registration_number': registrationNumber,
      'capacity_kg': capacityKg,
      'capacity_cbm': capacityCbm,
      'service_route': serviceRoute,
      'status': 'active',
    });
  }

  Future<void> delete(String id) async {
    await _client.delete('/fleet/$id');
  }
}

class ProductService {
  final ApiClient _client = ApiClient();

  Future<List<Product>> listMine() async {
    final res = await _client.get('/products/mine');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => Product.fromJson(e)).toList();
  }

  Future<List<Product>> search(String query) async {
    final res = await _client.get('/products', query: {'q': query});
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => Product.fromJson(e)).toList();
  }

  Future<void> create({
    required String name,
    String? hsnCode,
    String? description,
    required String unit,
    required double unitPrice,
    double minOrderQty = 1,
    String? imageUrl,
  }) async {
    await _client.post('/products', data: {
      'name': name,
      'hsn_code': hsnCode,
      'description': description,
      'unit': unit,
      'unit_price': unitPrice,
      'min_order_qty': minOrderQty,
      'image_url': imageUrl,
    });
  }

  Future<void> delete(String id) async {
    await _client.delete('/products/$id');
  }
}

class ApiKeyService {
  final ApiClient _client = ApiClient();

  /// Returns the raw key — shown once, never retrievable again.
  Future<String> generate({String? label}) async {
    final res = await _client.post('/api-keys', data: {'label': label});
    return res.data['data']['api_key'];
  }

  Future<List<dynamic>> listMine() async {
    final res = await _client.get('/api-keys');
    return res.data['data'] as List? ?? [];
  }

  Future<void> revoke(String id) async {
    await _client.delete('/api-keys/$id');
  }
}

class DirectoryService {
  final ApiClient _client = ApiClient();

  Future<List<LogisticsPartner>> listLogisticsPartners({String query = ''}) async {
    final res = await _client.get('/logistics/directory', query: {'q': query});
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => LogisticsPartner.fromJson(e)).toList();
  }
}

class MembershipService {
  final ApiClient _client = ApiClient();

  Future<Membership> getMine() async {
    final res = await _client.get('/membership/me');
    return Membership.fromJson(res.data['data']);
  }

  Future<Map<String, dynamic>> createPremiumOrder() async {
    final res = await _client.post('/membership/premium/order');
    return res.data['data'];
  }

  /// Self-declared "Payment Done" after the user returns from their UPI app.
  Future<void> verifyPremiumPayment() async {
    await _client.post('/membership/premium/verify');
  }

  Future<Map<String, dynamic>> createFeaturedOrder() async {
    final res = await _client.post('/membership/featured/order');
    return res.data['data'];
  }

  /// tier must be 'silver', 'gold', or 'enterprise'.
  Future<Map<String, dynamic>> createTierOrder(String tier) async {
    final res = await _client.post('/membership/subscribe/order', data: {'tier': tier});
    return res.data['data'];
  }

  Future<void> verifyTierPayment({required String tier}) async {
    await _client.post('/membership/subscribe/verify', data: {'tier': tier});
  }

  /// Self-declared "Payment Done" after the user returns from their UPI app.
  Future<void> verifyFeaturedPayment() async {
    await _client.post('/membership/featured/verify');
  }
}

class AdvertisementService {
  final ApiClient _client = ApiClient();

  Future<List<Advertisement>> listActive() async {
    final res = await _client.get('/ads/active');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => Advertisement.fromJson(e)).toList();
  }

  Future<List<Advertisement>> listMine() async {
    final res = await _client.get('/ads/mine');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => Advertisement.fromJson(e)).toList();
  }

  Future<Advertisement> create({
    required String title,
    String? description,
    String? category,
    required String mediaType,
    required String imageUrl,
    double? price,
    String? contactInfo,
    String? targetUrl,
  }) async {
    final res = await _client.post('/ads', data: {
      'title': title,
      'description': description,
      'category': category,
      'media_type': mediaType,
      'image_url': imageUrl,
      'price': price,
      'contact_info': contactInfo,
      'target_url': targetUrl,
    });
    return Advertisement.fromJson(res.data['data']);
  }

  Future<Advertisement> update(
    String id, {
    required String title,
    String? description,
    String? category,
    required String mediaType,
    required String imageUrl,
    double? price,
    String? contactInfo,
    String? targetUrl,
  }) async {
    await _client.put('/ads/$id', data: {
      'title': title,
      'description': description,
      'category': category,
      'media_type': mediaType,
      'image_url': imageUrl,
      'price': price,
      'contact_info': contactInfo,
      'target_url': targetUrl,
    });
    return getById(id);
  }

  Future<Advertisement> getById(String id) async {
    final res = await _client.get('/ads/$id');
    return Advertisement.fromJson(res.data['data']);
  }

  Future<void> setActive(String id, bool isActive) async {
    await _client.patch('/ads/$id/active', data: {'is_active': isActive});
  }

  Future<void> delete(String id) async {
    await _client.delete('/ads/$id');
  }
}
