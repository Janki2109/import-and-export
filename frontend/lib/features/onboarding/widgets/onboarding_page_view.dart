import 'package:flutter/material.dart';
import '../models/onboarding_page_data.dart';
import 'onboarding_effects.dart';
import 'scenes/onboarding_scenes.dart';

/// Layout for a single onboarding page: animated scene, optional highlight chip, emoji +
/// typewriter title, and description. Reused identically by every role's story — only the
/// [data] and [color] differ per page.
class OnboardingPageView extends StatelessWidget {
  final OnboardingPageData data;
  final Color color;
  const OnboardingPageView({super.key, required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OnboardingScene(data: data, color: color),
          const SizedBox(height: 20),
          if (data.highlight != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(
                data.highlight!.toUpperCase(),
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(data.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          TypewriterText(
            key: ValueKey(data.title),
            text: data.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            data.description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14.5, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7), height: 1.5),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
