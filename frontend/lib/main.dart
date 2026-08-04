import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'features/onboarding/services/app_guide_prefs.dart';
import 'l10n/generated/app_localizations.dart';
import 'providers/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Push notifications degrade gracefully — the app still works without Firebase
    // configured (e.g. google-services.json missing in a dev build).
    debugPrint('Firebase init failed, push notifications disabled: $e');
  }
  await AppGuidePrefs.preload();
  // Fire-and-forget: don't block the first frame on network resolution (up to a few
  // seconds). The splash screen shows for a minimum duration (~3.6s) before any API
  // call is made, which gives this plenty of time to complete in the background.
  // ignore: unawaited_futures
  AppConstants.resolveNetwork();
  runApp(const ProviderScope(child: OneBharatApp()));
}

class OneBharatApp extends ConsumerStatefulWidget {
  const OneBharatApp({super.key});

  @override
  ConsumerState<OneBharatApp> createState() => _OneBharatAppState();
}

class _OneBharatAppState extends ConsumerState<OneBharatApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    auth.tryAutoLogin();
    ref.read(themeProvider).load();
    ref.read(localeProvider).load();
    // GoRouter's redirect re-evaluates automatically whenever auth notifies listeners
    // (login/logout/auto-login resolving), so the root route always reflects the
    // current session state without any manual navigation calls from the screens.
    _router = buildRouter(auth);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: theme.mode,
      locale: locale.effectiveLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
