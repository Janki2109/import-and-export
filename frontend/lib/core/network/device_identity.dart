import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

const _deviceIdKey = 'security_device_id';

/// A stable, random per-install identifier — not a hardware ID (no permissions needed),
/// just a locally-generated random string persisted via SharedPreferences so the same
/// installation is recognized as "the same device" across app restarts. Sent as
/// X-Device-Id on every API request (see ApiClient) so the backend's device-management /
/// login-history features (Security Dashboard) have something to key off.
class DeviceIdentity {
  static String? _cached;
  static Future<String>? _inFlight;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    // Guard against concurrent callers each racing to generate/persist their own device id
    // (e.g. several API calls fired at startup before the first `get()` resolves) — everyone
    // awaits the same in-flight generation future instead.
    return _inFlight ??= _load();
  }

  static Future<String> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = _generate();
      await prefs.setString(_deviceIdKey, id);
    }
    _cached = id;
    _inFlight = null;
    return id;
  }

  static String _generate() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
