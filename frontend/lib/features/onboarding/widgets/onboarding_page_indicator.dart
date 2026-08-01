import 'package:flutter/material.dart';

/// Dot indicator whose active dot animates into a pill shape, plus a "3 / 8" progress
/// label — standard premium-onboarding convention (Duolingo/Revolut-style intros use the
/// same "expanding active dot + progress readout" pattern).
class OnboardingPageIndicator extends StatelessWidget {
  final int count;
  final int currentIndex;
  final Color color;
  const OnboardingPageIndicator({super.key, required this.count, required this.currentIndex, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(count, (i) {
            final active = i == currentIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: active ? color : color.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          '${currentIndex + 1} / $count',
          style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
