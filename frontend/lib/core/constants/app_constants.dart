import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

class AppConstants {
  // Physical device testing — phone and PC must be on the same Wi-Fi network.
  // This is the dev machine's LAN IP; update it if the machine's IP changes (DHCP).
  // AppConstants.resolveNetwork() probes this at startup and automatically falls back to
  // 10.0.2.2 (Android emulator's alias for the host machine) or localhost (iOS simulator)
  // if this address isn't reachable — see resolveNetwork() below.
  static const String _lanIp = '192.168.1.6';
  // Production backend, deployed on Render — used as the release-build default so a
  // plain `flutter build apk --release` (no --dart-define overrides) points at the live
  // API rather than a developer's LAN IP.
  static const String _prodHost = 'import-and-export-1.onrender.com';
  static const String _configuredHost = String.fromEnvironment(
    'API_HOST',
    defaultValue: kDebugMode ? _lanIp : _prodHost,
  );
  static const String _configuredScheme = String.fromEnvironment(
    'API_SCHEME',
    defaultValue: kDebugMode ? 'http' : 'https',
  );
  // Render serves the production backend on the standard HTTPS port (443, implicit);
  // only local dev (the LAN-IP backend above) runs on the explicit 8081 port.
  static const int _port = int.fromEnvironment('API_PORT', defaultValue: kDebugMode ? 8081 : 443);

  static String _host = _configuredHost;
  static const String _scheme = _configuredScheme;

  static String get baseUrl => '$_scheme://$_host:$_port/api/v1';

  /// Host root (no /api/v1) — used to resolve relative file_url paths returned by /documents endpoints.
  static String get fileHostUrl => '$_scheme://$_host:$_port';

  /// WebSocket endpoint for real-time chat — same host as baseUrl. Uses wss:// when the
  /// base scheme is https, ws:// only in plain-http debug mode.
  static String get chatWsUrl {
    const wsScheme = _scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://$_host:$_port/api/v1/ws/chat';
  }

  /// Probes the configured LAN IP at startup (short TCP connect, not an HTTP request) and
  /// switches to a platform-appropriate fallback if it's unreachable:
  ///   - Android emulator -> 10.0.2.2 (the emulator's alias for the host machine's localhost)
  ///   - iOS simulator     -> localhost (the simulator shares the host machine's network)
  /// Physical devices have no such alias, so if the configured host isn't reachable there,
  /// the address stays as configured — the resulting connection error will correctly point
  /// at the real (mis)configured host rather than silently masking it.
  /// Call once, awaited, before runApp(). Never throws.
  static Future<void> resolveNetwork() async {
    if (!kDebugMode) {
      // In release builds we trust the configured host/scheme (defaults to https) and
      // skip the LAN-IP auto-probe entirely.
      _host = _configuredHost;
      return;
    }
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
