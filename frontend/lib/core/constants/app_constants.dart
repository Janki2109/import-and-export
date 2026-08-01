import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

class AppConstants {
  // Physical device testing — phone and PC must be on the same Wi-Fi network.
  // This is the dev machine's LAN IP; update it if the machine's IP changes (DHCP).
  // AppConstants.resolveNetwork() probes this at startup and automatically falls back to
  // 10.0.2.2 (Android emulator's alias for the host machine) or localhost (iOS simulator)
  // if this address isn't reachable — see resolveNetwork() below.
  static const String _configuredHost = '192.168.1.6';
  static const int _port = 8081;

  static String _host = _configuredHost;

  static String get baseUrl => 'http://$_host:$_port/api/v1';

  /// Host root (no /api/v1) — used to resolve relative file_url paths returned by /documents endpoints.
  static String get fileHostUrl => 'http://$_host:$_port';

  /// WebSocket endpoint for real-time chat — same host as baseUrl, ws:// scheme.
  static String get chatWsUrl => 'ws://$_host:$_port/api/v1/ws/chat';

  /// Probes the configured LAN IP at startup (short TCP connect, not an HTTP request) and
  /// switches to a platform-appropriate fallback if it's unreachable:
  ///   - Android emulator -> 10.0.2.2 (the emulator's alias for the host machine's localhost)
  ///   - iOS simulator     -> localhost (the simulator shares the host machine's network)
  /// Physical devices have no such alias, so if the configured host isn't reachable there,
  /// the address stays as configured — the resulting connection error will correctly point
  /// at the real (mis)configured host rather than silently masking it.
  /// Call once, awaited, before runApp(). Never throws.
  static Future<void> resolveNetwork() async {
    if (await _reachable(_configuredHost)) {
      _host = _configuredHost;
      if (kDebugMode) debugPrint('[AppConstants] Backend reachable at $_configuredHost:$_port');
      return;
    }

    final fallback = Platform.isAndroid ? '10.0.2.2' : (Platform.isIOS ? 'localhost' : null);
    if (fallback != null && await _reachable(fallback)) {
      _host = fallback;
      if (kDebugMode) {
        debugPrint('[AppConstants] $_configuredHost:$_port unreachable — using emulator/simulator fallback $fallback:$_port');
      }
      return;
    }

    _host = _configuredHost;
    if (kDebugMode) {
      debugPrint('[AppConstants] WARNING: backend not reachable at $_configuredHost:$_port'
          '${fallback != null ? ' or fallback $fallback:$_port' : ''}. '
          'Is the backend running? Is AppConstants._configuredHost up to date with this machine\'s LAN IP?');
    }
  }

  static Future<bool> _reachable(String host) async {
    try {
      final socket = await Socket.connect(host, _port, timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  // Secure storage keys
  static const String tokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String roleKey = 'user_role';
  static const String userIdKey = 'user_id';
  static const String userNameKey = 'user_name';

  // Onboarding (shared_preferences, not secure storage — non-sensitive UI state)
  static const String onboardingSeenKey = 'onboarding_seen';
  static const String languageKey = 'app_language';

  static const String appName = 'One Bharat Export-Import';
}
