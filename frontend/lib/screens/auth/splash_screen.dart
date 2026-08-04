import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/providers.dart';
import 'auth_visuals.dart';

const _gold = Color(0xFFD4AF37);
// Deep royal-navy gradient — matches the native launch splash (#0A1A33, see
// flutter_native_splash.yaml / android adaptive-icon background) so the handoff from the
// OS's native splash into this Flutter screen is seamless, not a visible color jump.
const _navyDark = Color(0xFF0A1A33);
const _navyLight = Color(0xFF163A6B);

/// Premium animated startup splash — globe, orbiting plane, sliding ship, driving truck,
/// rotating trade arrows, light rays, soft particles, and a floating brand mark, over a
/// dark-royal-blue gradient with gold accents.
///
/// This is the *second* stage of the startup experience: the OS's native launch splash
/// (Android 12+ SplashScreen API / launch_background, configured via
/// flutter_native_splash.yaml) shows first, using the same navy background and the same
/// logo, then this screen takes over the instant Flutter's first frame is drawn and
/// continues the experience with the full animation for the remaining time.
///
/// Navigation stays router-driven (GoRouter's redirect in app_router.dart decides where an
/// unknown/unauthenticated/authenticated user belongs — this screen never duplicates that
/// logic, and unauthenticated always resolves straight to /login — no Welcome/Language step).
/// The only addition here is a *minimum display duration* gate: once both the intro
/// animation has finished AND [AuthProvider.tryAutoLogin] has resolved, this screen "pokes"
/// GoRouter by navigating to its own current location, which makes the redirect re-run
/// immediately with fresh auth state — without this, a fast auto-login could skip past the
/// splash before the user ever sees it. The route itself fades into Login (see the
/// CustomTransitionPage on '/login' in app_router.dart).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro; // one-shot, drives the whole reveal choreography
  late final AnimationController _loop; // continuous, drives globe/plane/ship/truck/particles/rays/float
  bool _minDurationElapsed = false;
  bool _navigated = false;
  bool _precached = false;
  String _version = '';

  static const _introDuration = Duration(milliseconds: 3600); // within the requested 3–4s

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: _introDuration)
      ..forward().whenComplete(() {
        if (mounted) setState(() => _minDurationElapsed = true);
        _maybeNavigate();
      });
    _loop = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      precacheImage(const AssetImage('assets/images/app_logo.png'), context);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _maybeNavigate() {
    if (_navigated || !_minDurationElapsed) return;
    if (ref.read(authProvider).status == AuthStatus.unknown) return; // still resolving — try again when it notifies
    _navigated = true;
    if (mounted) context.go('/splash'); // re-triggers GoRouter's redirect with current auth state
  }

  Animation<double> _seg(double start, double end, {Curve curve = Curves.easeOut}) {
    return CurvedAnimation(parent: _intro, curve: Interval(start, end, curve: curve));
  }

  @override
  Widget build(BuildContext context) {
    // Auth resolving faster/slower than the intro animation both funnel through here.
    ref.listen(authProvider, (previous, next) => _maybeNavigate());

    final backgroundReveal = _seg(0.0, 0.2);
    final logoReveal = _seg(0.1, 0.38, curve: Curves.easeOutBack);
    final glow = _seg(0.5, 0.9);
    final brandReveal = _seg(0.3, 0.55);
    final taglineReveal = _seg(0.5, 0.76);
    final subtitleReveal = _seg(0.66, 0.9);
    final versionReveal = _seg(0.82, 1.0);

    return Scaffold(
      backgroundColor: _navyDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1 — dark royal-blue gradient reveal.
          AnimatedBuilder(
            animation: _intro,
            builder: (context, child) => Opacity(opacity: backgroundReveal.value, child: child),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_navyDark, _navyLight], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              ),
            ),
          ),
          // Layer 2 — soft light rays sweeping slowly behind everything.
          AnimatedBuilder(animation: _loop, builder: (context, _) => CustomPaint(painter: _LightRaysPainter(t: _loop.value), size: Size.infinite)),
          // Layer 3 — soft particles.
          AnimatedBuilder(animation: _loop, builder: (context, _) => CustomPaint(painter: _ParticlePainter(t: _loop.value), size: Size.infinite)),
          // Layer 4 — globe, orbiting plane, sliding ship, driving truck, trade routes.
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_intro, _loop]),
              builder: (context, _) {
                return SizedBox(
                  width: 300,
                  height: 300,
                  child: Opacity(
                    opacity: backgroundReveal.value,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.rotate(angle: _loop.value * 2 * math.pi, child: const CustomPaint(size: Size(260, 260), painter: GlobePainter(color: Colors.white, strokeWidth: 0.9))),
                        // Orbiting plane.
                        Transform.rotate(
                          angle: _loop.value * 2 * math.pi,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Transform.rotate(angle: math.pi / 2, child: const Icon(Icons.flight, color: _gold, size: 22)),
                          ),
                        ),
                        // Sliding cargo ship along the base.
                        Positioned(
                          bottom: 36,
                          left: 20 + 220 * ((_loop.value * 1.4) % 1.0),
                          child: Opacity(opacity: 0.9, child: Icon(Icons.directions_boat_filled, color: Colors.white.withValues(alpha: 0.85), size: 20)),
                        ),
                        // Truck entering from the side, driving across.
                        Positioned(
                          bottom: 14,
                          left: -30 + 340 * ((_loop.value * 0.9) % 1.0),
                          child: Icon(Icons.local_shipping, color: _gold.withValues(alpha: 0.9), size: 18),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Centered content: logo (full, uncropped, transparent) + glow + rotating trade
          // arrows, brand name, tagline, subtitle.
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  height: 220,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_intro, _loop]),
                    builder: (context, _) {
                      final float = math.sin(_loop.value * 2 * math.pi) * 5;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Soft gold glow/pulse behind the logo.
                          Opacity(
                            opacity: (math.sin(glow.value * math.pi)).clamp(0, 1).toDouble(),
                            child: Container(
                              width: 190,
                              height: 190,
                              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: _gold.withValues(alpha: 0.45), blurRadius: 60, spreadRadius: 10)]),
                            ),
                          ),
                          // Rotating trade arrows ring.
                          Transform.rotate(angle: -_loop.value * 2 * math.pi, child: CustomPaint(size: const Size(210, 210), painter: _TradeArrowsPainter(color: Colors.white.withValues(alpha: 0.45)))),
                          // Logo — the full, transparent PNG, no crop/zoom/white backing,
                          // aspect ratio preserved. Scale-in, then a continuous gentle float.
                          Transform.translate(
                            offset: Offset(0, _minDurationElapsed ? float : 0),
                            child: Transform.scale(
                              scale: 0.8 + 0.2 * logoReveal.value,
                              child: Opacity(
                                opacity: logoReveal.value,
                                child: Image.asset('assets/images/app_logo.png', width: 168, height: 168, fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _intro,
                  builder: (context, child) => Opacity(
                    opacity: brandReveal.value,
                    child: Transform.translate(offset: Offset(0, (1 - brandReveal.value) * 8), child: child),
                  ),
                  child: const Column(
                    children: [
                      Text('ONE BHARAT', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3)),
                      SizedBox(height: 4),
                      Text('Export  •  Import  •  Connect', style: TextStyle(color: _gold, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                    ],
                  ),
                ),
                const SizedBox(height: 34),
                AnimatedBuilder(
                  animation: _intro,
                  builder: (context, child) => Opacity(
                    opacity: taglineReveal.value,
                    child: Transform.translate(offset: Offset(0, (1 - taglineReveal.value) * 10), child: child),
                  ),
                  child: const Text('Connecting Global Trade...', style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                ),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _intro,
                  builder: (context, child) => Opacity(opacity: subtitleReveal.value, child: child),
                  child: Text('Secure  •  Verified  •  Trusted', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                ),
              ],
            ),
          ),

          // Bottom — version number.
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: AnimatedBuilder(
              animation: _intro,
              builder: (context, child) => Opacity(opacity: versionReveal.value, child: child),
              child: Text(
                _version.isEmpty ? ' ' : 'v$_version',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two curved arrows rotating around the logo — the "trade routes" motif.
class _TradeArrowsPainter extends CustomPainter {
  final Color color;
  const _TradeArrowsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawArc(rect, -math.pi / 6, math.pi * 0.7, false, paint);
    canvas.drawArc(rect, math.pi - math.pi / 6, math.pi * 0.7, false, paint);
    // Arrowheads.
    final tip1 = Offset(size.width / 2 + (size.width / 2) * math.cos(math.pi * 0.7 - math.pi / 6), size.height / 2 + (size.height / 2) * math.sin(math.pi * 0.7 - math.pi / 6));
    final tip2 = Offset(size.width / 2 + (size.width / 2) * math.cos(math.pi + math.pi * 0.7 - math.pi / 6), size.height / 2 + (size.height / 2) * math.sin(math.pi + math.pi * 0.7 - math.pi / 6));
    canvas.drawCircle(tip1, 2.2, Paint()..color = color);
    canvas.drawCircle(tip2, 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TradeArrowsPainter oldDelegate) => oldDelegate.color != color;
}

/// Faint rotating light rays sweeping from the center outward — a slow, luxurious glow
/// effect (fintech/logistics splash screens use the same trick).
class _LightRaysPainter extends CustomPainter {
  final double t;
  const _LightRaysPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    const rayCount = 8;
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * 2 * math.pi + t * 2 * math.pi * 0.15;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + math.cos(angle - 0.05) * size.longestSide, center.dy + math.sin(angle - 0.05) * size.longestSide)
        ..lineTo(center.dx + math.cos(angle + 0.05) * size.longestSide, center.dy + math.sin(angle + 0.05) * size.longestSide)
        ..close();
      paint.color = Colors.white.withValues(alpha: 0.025);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LightRaysPainter oldDelegate) => oldDelegate.t != t;
}

class _Particle {
  final double x, size, speed, phase;
  _Particle(this.x, this.size, this.speed, this.phase);
}

class _ParticlePainter extends CustomPainter {
  final double t;
  _ParticlePainter({required this.t});

  static final List<_Particle> _particles = List.generate(
    22,
    (i) {
      final rnd = math.Random(i * 13);
      return _Particle(rnd.nextDouble(), 1.5 + rnd.nextDouble() * 2.5, 0.3 + rnd.nextDouble() * 0.6, rnd.nextDouble());
    },
  );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in _particles) {
      final progress = (t * p.speed + p.phase) % 1.0;
      final dy = size.height * (1 - progress);
      final dx = p.x * size.width + 14 * math.sin(progress * 4 * math.pi + p.phase * 10);
      final opacity = (math.sin(progress * math.pi)).clamp(0, 1).toDouble();
      canvas.drawCircle(Offset(dx, dy), p.size, paint..color = (p.phase > 0.5 ? _gold : Colors.white).withValues(alpha: 0.3 * opacity));
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => oldDelegate.t != t;
}
