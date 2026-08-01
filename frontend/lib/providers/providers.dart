import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'locale_provider.dart';
import 'theme_provider.dart';

/// AuthProvider/ThemeProvider/LocaleProvider stay plain ChangeNotifiers — Riverpod's
/// ChangeNotifierProvider wraps them as-is, keeping a single shared instance
/// across the app without rewriting their internals.
final authProvider = ChangeNotifierProvider<AuthProvider>((ref) => AuthProvider());
final themeProvider = ChangeNotifierProvider<ThemeProvider>((ref) => ThemeProvider());
final localeProvider = ChangeNotifierProvider<LocaleProvider>((ref) => LocaleProvider());
