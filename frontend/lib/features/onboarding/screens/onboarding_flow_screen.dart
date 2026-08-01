import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user.dart';
import '../../../providers/providers.dart';
import '../models/onboarding_content.dart';
import '../services/app_guide_prefs.dart';
import '../widgets/onboarding_effects.dart';
import '../widgets/onboarding_page_indicator.dart';
import '../widgets/onboarding_page_view.dart';

/// The premium, animated first-time app guide — role-specific (Importer/Exporter/
/// Logistics; never shown for Admin). Two ways this screen is reached, both purely
/// additive to existing navigation:
///   1. First login gate — registered as the '/app-guide' GoRouter route, inserted into the
///      redirect chain in app_router.dart right after onboarding (company+KYC) and before
///      the dashboard. Finishing/skipping marks the guide seen and routes to the dashboard.
///   2. "View App Guide" replay from Settings — pushed as a normal modal screen
///      (Navigator.push), same as every other sub-screen in this app. Finishing/skipping
///      just pops back to Settings; the "seen" flag is untouched (it's already true).
class OnboardingFlowScreen extends ConsumerStatefulWidget {
  /// True when opened via "View App Guide" (Settings) rather than the first-login gate.
  final bool isReplay;
  const OnboardingFlowScreen({super.key, this.isReplay = false});

  @override
  ConsumerState<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends ConsumerState<OnboardingFlowScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _roleColor(UserRole role, bool isDark) {
    switch (role) {
      case UserRole.importer:
        return isDark ? AppColorsDark.primary : AppColors.primary;
      case UserRole.exporter:
        return isDark ? AppColorsDark.secondary : AppColors.secondary;
      case UserRole.logistics:
        return isDark ? AppColorsDark.accent : AppColors.accent;
      case UserRole.admin:
        return isDark ? AppColorsDark.primary : AppColors.primary; // unreachable — admin never sees this screen
    }
  }

  Future<void> _finish() async {
    final auth = ref.read(authProvider);
    final user = auth.currentUser;
    if (widget.isReplay) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (user != null) {
      await AppGuidePrefs.markSeen(user.id);
    }
    if (mounted && user != null) {
      context.go(dashboardPathForRole(user.role));
    }
  }

  void _next(int pageCount) {
    if (_index < pageCount - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  void _previous() {
    if (_index > 0) {
      _controller.previousPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).currentUser?.role;
    if (role == null || role == UserRole.admin) {
      // Defensive — should never happen (router/settings gate this), but never crash.
      return const SizedBox.shrink();
    }

    final pages = OnboardingContent.forRole(role);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _roleColor(role, isDark);
    final isLastPage = _index == pages.length - 1;

    return PopScope(
      // Swallow back-button on the first-login gate (no dashboard to return to yet);
      // allow it on replay, where popping is exactly what Cancel/back should do.
      canPop: widget.isReplay,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Stack(
            children: [
              // Layer 1: slowly drifting gradient blobs — the "alive" backdrop.
              Positioned.fill(child: AnimatedGradientBackground(color: color)),
              // Layer 2: floating particles.
              Positioned.fill(child: FloatingParticles(color: color)),
              // Layer 3: the actual flow.
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isLastPage)
                          TextButton(
                            onPressed: _finish,
                            child: Text('Skip', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                          )
                        else
                          const SizedBox(height: 40), // keep header height stable across pages
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: pages.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => _PageEntrance(
                        key: ValueKey(i),
                        child: OnboardingPageView(data: pages[i], color: color),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      children: [
                        OnboardingPageIndicator(count: pages.length, currentIndex: _index, color: color),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            if (_index > 0) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _previous,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: color,
                                    side: BorderSide(color: color.withValues(alpha: 0.4)),
                                    padding: const EdgeInsets.symmetric(vertical: 15),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  child: const Text('Previous'),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              flex: _index > 0 ? 1 : 2,
                              child: GlowingButton(
                                label: isLastPage ? (pages[_index].ctaLabel ?? 'Get Started') : 'Next',
                                color: color,
                                onPressed: () => _next(pages.length),
                                icon: isLastPage ? Icons.arrow_forward_rounded : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade + gentle scale-up entrance for a freshly built page — layered on top of PageView's
/// own slide, so arriving at a page feels like more than a plain scroll.
class _PageEntrance extends StatefulWidget {
  final Widget child;
  const _PageEntrance({super.key, required this.child});

  @override
  State<_PageEntrance> createState() => _PageEntranceState();
}

class _PageEntranceState extends State<_PageEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 480))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: v,
          child: Transform.scale(scale: 0.94 + 0.06 * v, child: child),
        );
      },
      child: widget.child,
    );
  }
}
