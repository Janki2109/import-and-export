import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../l10n/generated/app_localizations.dart';

/// Persists the user's language preference (SharedPreferences — reuses the existing
/// [AppConstants.languageKey] the old language screen already wrote to) and drives the
/// app's live locale. The user can pick any of the platform's supported trade languages;
/// only the languages with a generated ARB translation ([AppLocalizations.supportedLocales])
/// actually change displayed text — any other selection is remembered (so it activates
/// automatically once translated) but the UI falls back to English in the meantime rather
/// than showing broken/missing strings.
class LocaleProvider extends ChangeNotifier {
  String? _languageCode;

  /// The raw selected code (e.g. 'fr'), even if not yet translated — used by the language
  /// screen to show the current selection and by Settings to display the chosen language.
  String? get languageCode => _languageCode;

  static final Set<String> _translatedCodes = AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();

  /// What MaterialApp should actually render with — falls back to English for any language
  /// that's selected but not yet translated.
  Locale get effectiveLocale {
    final code = _languageCode;
    if (code != null && _translatedCodes.contains(code)) return Locale(code);
    return const Locale('en');
  }

  bool get isFullyTranslated => _languageCode == null || _translatedCodes.contains(_languageCode);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _languageCode = prefs.getString(AppConstants.languageKey);
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.languageKey, code);
  }
}
