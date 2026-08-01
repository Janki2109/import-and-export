import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/onboarding_page_data.dart';

/// Dispatches to the bespoke animated widget for a page's [OnboardingSceneType]. Every scene
/// fills a fixed-height stage so page layout stays consistent regardless of which scene is
/// showing.
class OnboardingScene extends StatelessWidget {
  final OnboardingPageData data;
  final Color color;
  const OnboardingScene({super.key, required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    switch (data.scene) {
      case OnboardingSceneType.welcome:
        return _WelcomeScene(color: color);
      case OnboardingSceneType.document:
        return _DocumentScene(color: color, icon: data.sceneIcon);
      case OnboardingSceneType.cardsFlyIn:
        return _CardsFlyInScene(color: color);
      case OnboardingSceneType.negotiation:
        return _NegotiationScene(color: color);
      case OnboardingSceneType.escrow:
        return _EscrowScene(color: color);
      case OnboardingSceneType.shipment:
        return _ShipmentScene(color: color, icon: data.sceneIcon);
      case OnboardingSceneType.compliance:
        return _ComplianceScene(color: color);
      case OnboardingSceneType.celebration:
        return _CelebrationScene(color: color);
    }
  }
}

const _gold = Color(0xFFD4AF37);
const _stageHeight = 230.0;

/// ---------------------------------------------------------------------------------------
/// Scene 1 — Welcome: a rotating globe with glowing trade-route dots, a plane arcing over
/// the top, and a ship sliding along the base.
/// ---------------------------------------------------------------------------------------
class _WelcomeScene extends StatefulWidget {
  final Color color;
  const _WelcomeScene({required this.color});
  @override
  State<_WelcomeScene> createState() => _WelcomeSceneState();
}

class _WelcomeSceneState extends State<_WelcomeScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _stageHeight,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Rotating globe.
              Transform.rotate(
                angle: t * 2 * math.pi,
                child: CustomPaint(size: const Size(160, 160), painter: _GlobePainter(color: widget.color)),
              ),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [widget.color, widget.color.withValues(alpha: 0.6)])),
                child: const Icon(Icons.public, color: Colors.white, size: 46),
              ),
              // Plane arcing across the top.
              Positioned(
                top: 6 + 14 * math.sin(t * 2 * math.pi),
                left: 20 + (MediaQuery.of(context).size.width - 96) * ((t + 0.15) % 1.0),
                child: Transform.rotate(angle: 0.5, child: const Icon(Icons.flight, color: _gold, size: 22)),
              ),
              // Ship sliding along the base.
              Positioned(
                bottom: 18,
                left: 12 + (MediaQuery.of(context).size.width - 120) * ((t + 0.6) % 1.0),
                child: Icon(Icons.directions_boat_filled, color: widget.color.withValues(alpha: 0.8), size: 22),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlobePainter extends CustomPainter {
  final Color color;
  const _GlobePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius, paint);
    for (int i = 1; i < 4; i++) {
      canvas.drawOval(Rect.fromCenter(center: center, width: radius * 2, height: radius * 2 * (i / 4)), paint);
    }
    // Glowing trade-route dots.
    final dotPaint = Paint()..color = _gold;
    for (int i = 0; i < 6; i++) {
      final a = (i / 6) * 2 * math.pi;
      canvas.drawCircle(center + Offset(math.cos(a), math.sin(a)) * radius, 2.4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlobePainter oldDelegate) => false;
}

/// ---------------------------------------------------------------------------------------
/// Scene 2 — Document builds itself: form lines draw in one by one, then the action pill
/// glows to confirm submission.
/// ---------------------------------------------------------------------------------------
class _DocumentScene extends StatefulWidget {
  final Color color;
  final IconData icon;
  const _DocumentScene({required this.color, required this.icon});
  @override
  State<_DocumentScene> createState() => _DocumentSceneState();
}

class _DocumentSceneState extends State<_DocumentScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const lineCount = 4;
    return SizedBox(
      height: _stageHeight,
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            return Container(
              width: 210,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 12))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Icon(widget.icon, size: 18, color: widget.color),
                    const SizedBox(width: 8),
                    Container(width: 60, height: 8, decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4))),
                  ]),
                  const SizedBox(height: 16),
                  for (int i = 0; i < lineCount; i++) ...[
                    _AnimatedLine(progress: ((t * (lineCount + 1) - i)).clamp(0, 1).toDouble(), color: widget.color, widthFactor: i.isEven ? 1.0 : 0.7),
                    const SizedBox(height: 9),
                  ],
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Opacity(
                      opacity: ((t * (lineCount + 1) - lineCount)).clamp(0, 1).toDouble(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: widget.color,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 14)],
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 15),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AnimatedLine extends StatelessWidget {
  final double progress; // 0..1
  final double widthFactor;
  final Color color;
  const _AnimatedLine({required this.progress, required this.widthFactor, required this.color});
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: (widthFactor * progress).clamp(0, 1),
        child: Container(height: 7, decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(4))),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------------------
/// Scene 3 — Cards fly in from the right, staggered; the last one carries a gold "Best
/// Offer" ribbon and a verified badge.
/// ---------------------------------------------------------------------------------------
class _CardsFlyInScene extends StatefulWidget {
  final Color color;
  const _CardsFlyInScene({required this.color});
  @override
  State<_CardsFlyInScene> createState() => _CardsFlyInSceneState();
}

class _CardsFlyInSceneState extends State<_CardsFlyInScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _stageHeight,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (int i = 0; i < 3; i++) _flyingCard(i),
            ],
          );
        },
      ),
    );
  }

  Widget _flyingCard(int i) {
    final delay = i * 0.18;
    final raw = ((_c.value - delay) % 1.0);
    final entrance = Curves.easeOutBack.transform(raw.clamp(0, 0.4) / 0.4);
    final dx = (1 - entrance) * 140;
    final isBest = i == 2;
    return Positioned(
      top: 20.0 + i * 46,
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: Opacity(
          opacity: entrance.clamp(0, 1),
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: isBest ? Border.all(color: _gold, width: 1.4) : null,
              boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.storefront_outlined, size: 15, color: widget.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(children: [
                        Icon(Icons.verified, size: 12, color: Color(0xFF16A34A)),
                        SizedBox(width: 3),
                        Flexible(child: Text('Verified Exporter', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                      const SizedBox(height: 2),
                      Container(width: 70, height: 6, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3))),
                    ],
                  ),
                ),
                if (isBest)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(8)),
                    child: const Text('BEST', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------------------
/// Scene 4 — Negotiation: alternating chat bubbles fade/slide in, the price ticks down, and
/// a handshake glows once terms are reached.
/// ---------------------------------------------------------------------------------------
class _NegotiationScene extends StatefulWidget {
  final Color color;
  const _NegotiationScene({required this.color});
  @override
  State<_NegotiationScene> createState() => _NegotiationSceneState();
}

class _NegotiationSceneState extends State<_NegotiationScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _stageHeight,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final bubble1 = (t * 4).clamp(0, 1).toDouble();
          final bubble2 = ((t * 4) - 1).clamp(0, 1).toDouble();
          final bubble3 = ((t * 4) - 2).clamp(0, 1).toDouble();
          final handshake = ((t * 4) - 3).clamp(0, 1).toDouble();
          final price = 120 - (20 * bubble2).round();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _bubble('Can you do ₹$price/unit?', bubble1, alignRight: false, color: widget.color),
                const SizedBox(height: 8),
                _bubble('Deal — ₹$price/unit works!', bubble2, alignRight: true, color: _gold),
                const SizedBox(height: 18),
                Opacity(
                  opacity: handshake,
                  child: Transform.scale(
                    scale: 0.7 + 0.3 * handshake,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.color,
                        boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 20)],
                      ),
                      child: const Icon(Icons.handshake, color: Colors.white, size: 26),
                    ),
                  ),
                ),
                if (bubble3 > 0 && handshake == 0) const SizedBox(height: 0), // keep layout stable
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bubble(String text, double reveal, {required bool alignRight, required Color color}) {
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset((1 - reveal) * (alignRight ? 40 : -40), 0),
        child: Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: alignRight ? color : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(alignRight ? 16 : 4),
                bottomRight: Radius.circular(alignRight ? 4 : 16),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Text(text, style: TextStyle(color: alignRight ? Colors.white : Colors.black87, fontSize: 12.5, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------------------
/// Scene 5 — Escrow: coins flow down into a shield/vault while a milestone ring fills.
/// ---------------------------------------------------------------------------------------
class _EscrowScene extends StatefulWidget {
  final Color color;
  const _EscrowScene({required this.color});
  @override
  State<_EscrowScene> createState() => _EscrowSceneState();
}

class _EscrowSceneState extends State<_EscrowScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _stageHeight,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: CircularProgressIndicator(value: t, strokeWidth: 6, backgroundColor: widget.color.withValues(alpha: 0.12), valueColor: const AlwaysStoppedAnimation(_gold)),
              ),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color, boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.4), blurRadius: 20)]),
                child: Icon(t > 0.92 ? Icons.lock : Icons.shield_outlined, color: Colors.white, size: 42),
              ),
              for (int i = 0; i < 3; i++) _coin(i, t),
            ],
          );
        },
      ),
    );
  }

  Widget _coin(int i, double t) {
    final delay = i * 0.3;
    final raw = ((t - delay) % 1.0).clamp(0, 1).toDouble();
    final dy = -90 + 90 * raw;
    final opacity = (1 - raw).clamp(0, 1).toDouble();
    return Positioned(
      top: 110 + dy,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: _gold),
          child: const Icon(Icons.currency_rupee, size: 12, color: Colors.white),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------------------
/// Scene 6 — Shipment: a dashed route draws itself while a vehicle icon follows it end to
/// end, with a pulsing "live" dot at the destination.
/// ---------------------------------------------------------------------------------------
class _ShipmentScene extends StatefulWidget {
  final Color color;
  final IconData icon;
  const _ShipmentScene({required this.color, required this.icon});
  @override
  State<_ShipmentScene> createState() => _ShipmentSceneState();
}

class _ShipmentSceneState extends State<_ShipmentScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _stageHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth - 60;
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final path = _buildPath(w);
              final metrics = path.computeMetrics().toList();
              Offset pos = const Offset(30, _stageHeight / 2);
              double angle = 0;
              if (metrics.isNotEmpty) {
                final metric = metrics.first;
                final tangent = metric.getTangentForOffset(metric.length * t);
                if (tangent != null) {
                  pos = tangent.position;
                  angle = tangent.angle;
                }
              }
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: CustomPaint(painter: _RoutePainter(path: path, progress: t, color: widget.color))),
                  // Origin marker.
                  const Positioned(left: 24, top: _stageHeight / 2 - 5, child: _Dot(color: Colors.black26)),
                  // Destination marker — pulses.
                  Positioned(right: 24, top: _stageHeight / 2 - 5, child: _PulsingDot(color: widget.color)),
                  Positioned(
                    left: pos.dx - 14,
                    top: pos.dy - 14,
                    child: Transform.rotate(
                      angle: angle,
                      child: Icon(widget.icon, color: widget.color, size: 26),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Path _buildPath(double w) {
    final path = Path()..moveTo(30, _stageHeight / 2);
    path.quadraticBezierTo(30 + w / 2, _stageHeight / 2 - 70, 30 + w, _stageHeight / 2);
    return path;
  }
}

class _RoutePainter extends CustomPainter {
  final Path path;
  final double progress;
  final Color color;
  const _RoutePainter({required this.path, required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);
    final dashed = Path();
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        const dash = 6.0, gap = 5.0;
        dashed.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
        d += dash + gap;
      }
    }
    canvas.drawPath(dashed, Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    canvas.drawPath(drawn, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) => oldDelegate.progress != progress;
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) => Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
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
      builder: (context, _) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 10 + 16 * _c.value,
            height: 10 + 16 * _c.value,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35 * (1 - _c.value))),
          ),
          Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------------------
/// Scene 7 — Compliance: a checklist ticks green item by item while the progress bar fills
/// to 100%.
/// ---------------------------------------------------------------------------------------
class _ComplianceScene extends StatefulWidget {
  final Color color;
  const _ComplianceScene({required this.color});
  @override
  State<_ComplianceScene> createState() => _ComplianceSceneState();
}

class _ComplianceSceneState extends State<_ComplianceScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  static const _labels = ['Commercial Invoice', 'Packing List', 'Certificate of Origin'];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _stageHeight,
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final n = _labels.length;
            final progress = (t * (n + 1)).clamp(0, n + 1) / (n + 1);
            return Container(
              width: 230,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10))]),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < n; i++) ...[
                    _checkRow(_labels[i], (t * (n + 1) - i).clamp(0, 1).toDouble()),
                    if (i != n - 1) const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: widget.color.withValues(alpha: 0.12), valueColor: const AlwaysStoppedAnimation(Color(0xFF16A34A))),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _checkRow(String label, double done) {
    final checked = done > 0.5;
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 20,
          height: 20,
          decoration: BoxDecoration(shape: BoxShape.circle, color: checked ? const Color(0xFF16A34A) : Colors.grey.shade200),
          child: checked ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: checked ? Colors.black87 : Colors.black38), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------------------
/// Final scene — confetti burst behind a bouncing brand mark.
/// ---------------------------------------------------------------------------------------
class _CelebrationScene extends StatefulWidget {
  final Color color;
  const _CelebrationScene({required this.color});
  @override
  State<_CelebrationScene> createState() => _CelebrationSceneState();
}

class _ConfettiPiece {
  final double x, size, speed, phase, hue;
  _ConfettiPiece(this.x, this.size, this.speed, this.phase, this.hue);
}

class _CelebrationSceneState extends State<_CelebrationScene> with TickerProviderStateMixin {
  late final AnimationController _confetti;
  late final AnimationController _logo;
  late final List<_ConfettiPiece> _pieces;
  static const _palette = [_gold, Color(0xFF16A34A), Color(0xFF2563EB), Colors.white];

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(3);
    _pieces = List.generate(26, (_) => _ConfettiPiece(rnd.nextDouble(), 4 + rnd.nextDouble() * 4, 0.4 + rnd.nextDouble() * 0.6, rnd.nextDouble(), rnd.nextDouble()));
    _confetti = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _logo = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  }

  @override
  void dispose() {
    _confetti.dispose();
    _logo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _stageHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _confetti,
            builder: (context, _) => CustomPaint(painter: _ConfettiPainter(pieces: _pieces, t: _confetti.value, palette: _palette), size: const Size(double.infinity, _stageHeight)),
          ),
          AnimatedBuilder(
            animation: _logo,
            builder: (context, _) {
              final bounce = Curves.elasticOut.transform(_logo.value);
              return Transform.scale(
                scale: bounce,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [widget.color, widget.color.withValues(alpha: 0.7)]),
                    boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 30)],
                  ),
                  child: const Icon(Icons.celebration, color: Colors.white, size: 50),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double t;
  final List<Color> palette;
  const _ConfettiPainter({required this.pieces, required this.t, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < pieces.length; i++) {
      final p = pieces[i];
      final progress = (t * p.speed + p.phase) % 1.0;
      final dy = size.height * progress;
      final dx = p.x * size.width + 20 * math.sin(progress * 6 * math.pi + p.phase * 10);
      final color = palette[i % palette.length].withValues(alpha: (1 - progress).clamp(0, 1).toDouble());
      final rect = Rect.fromCenter(center: Offset(dx, dy), width: p.size, height: p.size * 1.6);
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(progress * 8 * math.pi * p.hue);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      canvas.drawRect(rect, Paint()..color = color);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
