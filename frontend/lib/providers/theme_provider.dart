import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'theme_mode';

/// Persists the user's light/dark/system preference across app restarts via shared_preferences.
class ThemeProvider extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeModeKey);
    switch (saved) {
      case 'light':
        mode = ThemeMode.light;
        break;
      case 'dark':
        mode = ThemeMode.dark;
        break;
      default:
        mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    final isCurrentlyDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system && WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
    mode = isCurrentlyDark ? ThemeMode.light : ThemeMode.dark;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }
}
