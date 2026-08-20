import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Shared premium presentation kit for the Admin Panel's Quick Action pages (Users, Orders,
/// Shipments, Payments, RFQs, KYC, etc.) — UI/UX ONLY. Every widget here is purely
/// presentational: it renders whatever real data/callbacks the calling screen already had,
/// with no new data fetching, no new API calls, and no behavior changes. Applied consistently
/// across every admin_*_screen.dart file so the whole Admin Panel reads as one design system.

/// Gradient AppBar matching the Admin Dashboard's header — used in place of a plain
/// `AppBar(title: Text(...))` on every admin sub-screen. Accepts the same `bottom`/`actions`
/// any AppBar would, so existing tabs/search/export icons keep working unchanged.
class AdminGradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final PreferredSizeWidget? bottom;
  final List<Widget>? actions;
  final Widget? leading;
  const AdminGradientAppBar({super.key, required this.title, this.bottom, this.actions, this.leading});

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      title: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title)),
      leading: leading,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark ? [AppColorsDark.primary, AppColorsDark.secondary] : [const Color(0xFF0B3D91), const Color(0xFF1857C4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      bottom: bottom,
      actions: actions,
    );
  }
}

/// Soft, mostly-neutral page background with two subtle decorative blurred circles — wraps a
/// screen's body content. Deliberately low-contrast so it never fights with card content or
/// hurts readability, per "clean modern light background... do NOT make it distracting".
class AdminPageBackground extends StatelessWidget {
  final Widget child;
  const AdminPageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: isDark ? 0.06 : 0.05)),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.secondary.withValues(alpha: isDark ? 0.05 : 0.04)),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Press-scale micro-interaction — identical pattern already used on the Importer/Exporter/
/// Logistics/Admin dashboards, exported here so every admin sub-screen can share one copy
/// instead of re-declaring it privately per file.
class AdminTapScale extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final BorderRadius? borderRadius;
  const AdminTapScale({super.key, required this.onTap, required this.child, this.borderRadius});

  @override
  State<AdminTapScale> createState() => _AdminTapScaleState();
}

class _AdminTapScaleState extends State<AdminTapScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          borderRadius: widget.borderRadius,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: widget.borderRadius,
            splashColor: AppColors.primary.withValues(alpha: 0.12),
            highlightColor: AppColors.primary.withValues(alpha: 0.06),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Staggered fade + slide entrance for list items/cards, delayed by [index]. Same pattern
/// used across the role dashboards.
class AdminReveal extends StatelessWidget {
  final int index;
  final Widget child;
  const AdminReveal({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (index * 25).clamp(0, 260)),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: c)),
      child: child,
    );
  }
}

/// A rounded, soft-shadow card — the standard content container used across admin sub-screens
/// for list items and detail sections, replacing plain `Container`/`Card` decorations.
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color accent;
  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
    this.accent = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return AdminTapScale(onTap: onTap, borderRadius: BorderRadius.circular(18), child: card);
  }
}

/// Modern pill status badge — a colored dot + label, replacing the many ad-hoc
/// `Container(decoration: BoxDecoration(color: ...withValues...` status chips scattered
/// across admin screens with one consistent look. Caller supplies the label/color exactly as
/// their existing logic already computed it — no status semantics change.
class AdminStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const AdminStatusBadge({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// A round gradient icon container — the small colorful icon badge used at the start of
/// list-item cards and section headers throughout the admin screens.
class AdminIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const AdminIconBadge({super.key, required this.icon, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.65)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.48),
    );
  }
}

/// Search field styled to match the rest of the admin kit — a drop-in replacement for the
/// plain `TextField(decoration: InputDecoration(...))` search bars used across admin screens.
class AdminSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  const AdminSearchField({super.key, required this.hint, required this.onChanged, this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Theme.of(context).cardTheme.color,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }
}

/// Section title with a small colored icon badge — consistent visual hierarchy marker used
/// above content blocks/lists on admin screens.
class AdminSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Widget? trailing;
  const AdminSectionHeader({super.key, required this.icon, required this.title, this.color = AppColors.primary, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2))),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Empty-state placeholder — consistent icon + title + subtitle used when a list has no items.
class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const AdminEmptyState({super.key, required this.icon, required this.title, this.subtitle = ''});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.12), AppColors.primary.withValues(alpha: 0.04)]), shape: BoxShape.circle),
              child: Icon(icon, size: 38, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }
}
