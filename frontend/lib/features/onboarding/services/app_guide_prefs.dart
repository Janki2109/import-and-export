import 'package:shared_preferences/shared_preferences.dart';

/// Local-only "has this user seen the app guide" flag — SharedPreferences, never the
/// database. Keyed per user id so multiple accounts on the same device (or a re-registered
/// user) each get their own first-run guide. Mirrors the existing OnboardingPrefs pattern
/// (app_router.dart) so the router's redirect can check it synchronously: call [preload]
/// once at startup (main.dart) before the router is built.
class AppGuidePrefs {
  static const _keyPrefix = 'app_guide_seen_';

  /// In-memory cache of user ids known to have completed/skipped the guide, populated by
  /// [preload] and kept in sync by [markSeen]. GoRouter's redirect must be synchronous, so
  /// it reads this set rather than awaiting SharedPreferences on every navigation.
  static final Set<String> _seenUserIds = {};

  static Future<void> preload() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_keyPrefix) && (prefs.getBool(key) ?? false)) {
        _seenUserIds.add(key.substring(_keyPrefix.length));
      }
    }
  }

  static bool hasSeen(String userId) => _seenUserIds.contains(userId);

  static Future<void> markSeen(String userId) async {
    _seenUserIds.add(userId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_keyPrefix$userId', true);
  }
}
