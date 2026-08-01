import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Slowly drifting soft gradient + glow blobs behind every onboarding scene — the "alive
/// background" that makes the flow feel premium instead of static. Pure Flutter (no image
/// assets), cheap to paint (few large blurred circles, not per-pixel work).
class AnimatedGradientBackground extends StatefulWidget {
  final Color color;
  const AnimatedGradientBackground({super.key, required this.color});

  @override
  State<AnimatedGradientBackground> createState() => _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
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
      builder: (context, _) {
        final t = _c.value * 2 * math.pi;
        return Stack(
          children: [
            Positioned(
              left: -80 + 40 * math.sin(t),
              top: -60 + 30 * math.cos(t * 0.8),
              child: _blob(220, widget.color.withValues(alpha: 0.14)),
            ),
            Positioned(
              right: -100 + 30 * math.cos(t * 0.6),
              top: 120 + 40 * math.sin(t * 0.7),
              child: _blob(260, const Color(0xFFD4AF37).withValues(alpha: 0.10)), // gold accent
            ),
            Positioned(
              left: -60 + 50 * math.cos(t * 0.5),
              bottom: -80 + 30 * math.sin(t * 0.9),
              child: _blob(240, widget.color.withValues(alpha: 0.10)),
            ),
          ],
        );
      },
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

/// Slowly rising, gently drifting particles — evokes "floating trade" without any asset
/// files. Painted once per frame via CustomPainter (cheap: a handful of circles).
class FloatingParticles extends StatefulWidget {
  final Color color;
  final int count;
  const FloatingParticles({super.key, required this.color, this.count = 18});

  @override
  State<FloatingParticles> createState() => _FloatingParticlesState();
}

class _Particle {
  final double x, size, speed, phase;
  _Particle(this.x, this.size, this.speed, this.phase);
}

class _FloatingParticlesState extends State<FloatingParticles> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _particles = List.generate(widget.count, (_) => _Particle(rnd.nextDouble(), 2 + rnd.nextDouble() * 3, 0.3 + rnd.nextDouble() * 0.7, rnd.nextDouble()));
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
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
      builder: (context, _) => CustomPaint(
        painter: _ParticlePainter(particles: _particles, t: _c.value, color: widget.color),
        size: Size.infinite,
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  final Color color;
  const _ParticlePainter({required this.particles, required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final p in particles) {
      final progress = (t * p.speed + p.phase) % 1.0;
      final dy = size.height * (1 - progress);
      final dx = p.x * size.width + 12 * math.sin(progress * 4 * math.pi + p.phase * 10);
      final opacity = (math.sin(progress * math.pi)).clamp(0, 1).toDouble(); // fade in/out at top & bottom
      canvas.drawCircle(Offset(dx, dy), p.size, paint..color = color.withValues(alpha: 0.25 * opacity));
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => oldDelegate.t != t;
}

/// Title text that types itself out character by character once per page arrival.
class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  const TypewriterText({super.key, required this.text, this.style, this.textAlign = TextAlign.center});

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    final duration = Duration(milliseconds: (widget.text.length * 28).clamp(300, 1400));
    _c = AnimationController(vsync: this, duration: duration)..forward();
  }

  @override
  void didUpdateWidget(covariant TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _c.duration = Duration(milliseconds: (widget.text.length * 28).clamp(300, 1400));
      _c.forward(from: 0);
    }
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
      builder: (context, _) {
        final chars = (widget.text.length * _c.value).round().clamp(0, widget.text.length);
        return Text(widget.text.substring(0, chars), style: widget.style, textAlign: widget.textAlign, maxLines: 2, overflow: TextOverflow.ellipsis);
      },
    );
  }
}

/// A premium CTA button: subtle continuous glow pulse + a tactile scale-down bounce on tap.
class GlowingButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final IconData? icon;
  const GlowingButton({super.key, required this.label, required this.color, required this.onPressed, this.icon});

  @override
  State<GlowingButton> createState() => _GlowingButtonState();
}

class _GlowingButtonState extends State<GlowingButton> with TickerProviderStateMixin {
  late final AnimationController _glow;
  late final AnimationController _tap;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _tap = AnimationController(vsync: this, duration: const Duration(milliseconds: 120), lowerBound: 0, upperBound: 0.06, value: 0);
  }

  @override
  void dispose() {
    _glow.dispose();
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_glow, _tap]),
      builder: (context, child) {
        final scale = 1 - _tap.value;
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.30 + 0.20 * _glow.value), blurRadius: 24 + 10 * _glow.value, offset: const Offset(0, 8))],
            ),
            child: child,
          ),
        );
      },
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () async {
            await _tap.forward();
            await _tap.reverse();
            widget.onPressed();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 18), const SizedBox(width: 8)],
              Flexible(child: Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted glassmorphism card wrapper — used for highlight chips and small overlay elements
/// inside scenes. Cheap: a semi-transparent tinted container with a light border, no
/// BackdropFilter blur (keeps scene animations at 60fps on low-end Android devices).
class GlassChip extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GlassChip({super.key, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: child,
    );
  }
}
