import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Shared subtle decorative page background — two soft blurred circles over the scaffold
/// background color. Used across the Importer/Exporter/Logistics dashboards (and mirrors
/// the same pattern already used for the Admin Panel's AdminPageBackground) so every
/// role's dashboard reads as the same premium design system. Purely presentational —
/// paints behind whatever `child` already renders, no layout/behavior change.
class PremiumPageBackground extends StatelessWidget {
  final Widget child;
  const PremiumPageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        children: [
          Positioned(
            top: -70,
            right: -70,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: isDark ? 0.06 : 0.05)),
            ),
          ),
          Positioned(
            bottom: -90,
            left: -90,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.secondary.withValues(alpha: isDark ? 0.05 : 0.04)),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
