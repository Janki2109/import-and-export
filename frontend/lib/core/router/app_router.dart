import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/onboarding/screens/onboarding_flow_screen.dart';
import '../../features/onboarding/services/app_guide_prefs.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../screens/admin/admin_dashboard.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/auth/splash_screen.dart';
import '../../screens/exporter/exporter_dashboard.dart';
import '../../screens/importer/importer_dashboard.dart';
import '../../screens/logistics/logistics_dashboard.dart';
import '../../screens/onboarding/create_company_screen.dart';
import '../../screens/shared/kyc_screen.dart';

String dashboardPathForRole(UserRole role) {
  switch (role) {
    case UserRole.importer:
      return '/importer';
    case UserRole.exporter:
      return '/exporter';
    case UserRole.logistics:
      return '/logistics';
    case UserRole.admin:
      return '/admin';
  }
}

const _preAuthPaths = ['/login', '/register'];
const _onboardingGatePaths = [
  '/login', '/register', '/splash', '/create-company', '/kyc-onboarding',
];

/// Root navigation is entirely GoRouter-driven, expressed as a redirect over
/// [AuthProvider] + onboarding flags:
///
///   Splash -> Login/Register -> Create Company -> KYC -> Dashboard
///
/// No Welcome/Language intro — the native+Flutter splash (see splash_screen.dart) fades
/// straight into Login. Language is still available anytime from Settings > Change Language
/// (a plain Navigator.push from ProfileScreen, not part of this redirect chain).
///
/// Admins skip Create Company/KYC entirely (there's no admin registration route — the one
/// admin account is server-bootstrapped and goes straight to /admin after login).
///
/// Sub-screens (RFQ detail, chat, wallet, etc.) still use plain Navigator.push from within
/// the dashboards — a supported, idiomatic mix with GoRouter, and it keeps this redirect
/// focused on the part that actually needs centralizing: where does the user belong right now.
GoRouter buildRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LoginScreen(),
          transitionDuration: const Duration(milliseconds: 450),
          transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
        ),
      ),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/create-company', builder: (context, state) => const CreateCompanyScreen()),
      GoRoute(path: '/kyc-onboarding', builder: (context, state) => const KYCScreen()),
      GoRoute(path: '/app-guide', builder: (context, state) => const OnboardingFlowScreen()),
      GoRoute(path: '/importer', builder: (context, state) => const ImporterDashboard()),
      GoRoute(path: '/exporter', builder: (context, state) => const ExporterDashboard()),
      GoRoute(path: '/logistics', builder: (context, state) => const LogisticsDashboard()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminDashboard()),
    ],
    redirect: (context, state) {
      final loc = state.matchedLocation;

      if (auth.status == AuthStatus.unknown) {
        return loc == '/splash' ? null : '/splash';
      }

      if (auth.status == AuthStatus.unauthenticated) {
        if (_preAuthPaths.contains(loc)) return null;
        return '/login';
      }

      // authenticated
      final user = auth.currentUser;
      if (user == null) {
        // Shouldn't happen while status == authenticated, but guard rather than force-unwrap
        // and dead-end navigation if state is ever inconsistent.
        return loc == '/login' ? null : '/login';
      }
      final isAdmin = user.role == UserRole.admin;

      // companyExists/kycStatus are null until refreshOnboardingStatus() resolves — that means
      // "not checked yet", not "false". Redirecting on null would bounce the user to
      // create-company/kyc-onboarding prematurely; instead stay put (splash/current route)
      // until the real value is known.
      if (!isAdmin && auth.companyExists == null) {
        return null;
      }
      final companyDone = isAdmin || (auth.companyExists == true);
      if (!companyDone) {
        return loc == '/create-company' ? null : '/create-company';
      }

      // Gate on a KYC row existing, not on admin approval — submitting once lets the user
      // into the dashboard (with full access unlocked only after the admin marks it
      // 'verified', enforced by individual screens/backend); admin review happens in the
      // background rather than blocking navigation.
      if (!isAdmin && auth.kycStatus == null && auth.kycSubmitted == null) {
        // Not checked yet — wait rather than treating as "not done".
        return null;
      }
      final kycDone = isAdmin || (auth.kycSubmitted == true);
      if (!kycDone) {
        return loc == '/kyc-onboarding' ? null : '/kyc-onboarding';
      }

      // First-time app guide — additive, role-specific, never shown to admin. Only gates
      // navigation once per user (AppGuidePrefs, local SharedPreferences flag); reopening it
      // later via Settings' "View App Guide" is a plain Navigator.push, not this redirect.
      final needsAppGuide = !isAdmin && !AppGuidePrefs.hasSeen(user.id);
      if (needsAppGuide) {
        return loc == '/app-guide' ? null : '/app-guide';
      }

      final target = dashboardPathForRole(user.role);
      if (_onboardingGatePaths.contains(loc) || loc == '/app-guide') {
        return target;
      }
      return null;
    },
  );
}
