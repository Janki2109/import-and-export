import 'package:flutter/material.dart';

/// Brand palette for the Auth flow (Splash/Login/Register) only — scoped here rather than
/// changed globally in AppColors, since the redesign brief is explicitly limited to these
/// three screens and the rest of the app's branding must stay exactly as-is.
class AuthColors {
  static const primary = Color(0xFF0B5ED7);
  static const secondary = Color(0xFF1E88E5);
  static const accent = Color(0xFFF9A825);
  static const background = Color(0xFFF8FAFC);
  static const textPrimary = Color(0xFF0F1B2D);
  static const textSecondary = Color(0xFF64748B);
  static const error = Color(0xFFDC2626);

  static const gradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Wireframe globe — concentric latitude ellipses + longitude arcs, drawn thin and mostly
/// transparent. Used as a quiet backdrop motif (splash) and a static top-section illustration
/// (login/register) — never animated as a "floating object", just a fixed painted layer.
class GlobePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  const GlobePainter({required this.color, this.strokeWidth = 1.1});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, paint);

    // Longitude arcs (meridians) — 4 vertical ellipses of decreasing width.
    for (final widthFactor in [1.0, 0.72, 0.4]) {
      canvas.drawOval(
        Rect.fromCenter(center: center, width: radius * 2 * widthFactor, height: radius * 2),
        paint,
      );
    }
    // Latitude lines (parallels) — horizontal ellipses of decreasing height.
    for (final heightFactor in [0.62, 0.28]) {
      canvas.drawOval(
        Rect.fromCenter(center: center, width: radius * 2, height: radius * 2 * heightFactor),
        paint,
      );
    }
    // Equator
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), paint);
  }

  @override
  bool shouldRepaint(covariant GlobePainter oldDelegate) => oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Static (non-floating, non-bouncing) trade motif for the top section of Login/Register —
/// a globe wireframe with a few flat, professional icon accents layered at fixed positions.
/// No animation, no drop shadows imitating "floating" objects.
class TradeIllustration extends StatelessWidget {
  final double size;
  const TradeIllustration({super.key, this.size = 190});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: GlobePainter(color: Colors.white.withValues(alpha: 0.35)),
          ),
          Positioned(
            bottom: size * 0.14,
            left: size * 0.06,
            child: Icon(Icons.directions_boat_filled_outlined, color: Colors.white.withValues(alpha: 0.9), size: size * 0.22),
          ),
          Positioned(
            top: size * 0.08,
            right: size * 0.1,
            child: Transform.rotate(
              angle: 0.5,
              child: Icon(Icons.flight_outlined, color: Colors.white.withValues(alpha: 0.85), size: size * 0.16),
            ),
          ),
          Positioned(
            bottom: size * 0.1,
            right: size * 0.08,
            child: Icon(Icons.inventory_2_outlined, color: Colors.white.withValues(alpha: 0.8), size: size * 0.15),
          ),
          Icon(Icons.public, color: Colors.white.withValues(alpha: 0.95), size: size * 0.3),
        ],
      ),
    );
  }
}

/// Circular brand mark with a soft shadow — used on Login/Register (Splash has its own
/// animated version with the rotating ring + glow).
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AuthColors.gradient,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: AuthColors.primary.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Icon(Icons.public, color: Colors.white, size: size * 0.5),
    );
  }
}

/// Large gradient button with a leading icon and ripple — the shared "primary action" style
/// across Login/Register.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;
  const GradientButton({super.key, required this.label, required this.icon, required this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: AuthColors.gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled ? [BoxShadow(color: AuthColors.primary.withValues(alpha: 0.32), blurRadius: 18, offset: const Offset(0, 8))] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onPressed : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.6,
            child: Center(
              child: loading
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 10),
                        Icon(icon, color: Colors.white, size: 20),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "OR" divider used between the primary gradient button and the social sign-in buttons.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('OR', style: TextStyle(color: AuthColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }
}

/// Outlined "Continue with X" button — UI only, per spec. Tapping shows a snackbar rather
/// than silently doing nothing or pretending to sign the user in.
class SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  const SocialButton({super.key, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label sign-in is coming soon.')),
        ),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: Colors.grey.shade300),
          foregroundColor: AuthColors.textPrimary,
        ),
        icon: icon,
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
      ),
    );
  }
}

/// Premium filled input decoration shared by Login/Register text fields — floating label,
/// rounded corners, focus-color border animation (built into Flutter's InputDecorator).
InputDecoration authFieldDecoration({
  required String label,
  required IconData icon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: AuthColors.textSecondary, size: 21),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: AuthColors.background,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AuthColors.primary, width: 1.6)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AuthColors.error, width: 1.4)),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
  );
}
