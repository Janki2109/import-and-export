import 'package:flutter/material.dart';

/// Which bespoke animated scene a page renders (see widgets/scenes/). Every enum value maps
/// to one hand-built animation widget; several are intentionally reused across roles with
/// different copy/color (e.g. [shipment] powers Global Shipment for the importer and Deliver
/// Successfully for logistics — same "route + moving vehicle" animation, different framing).
enum OnboardingSceneType { welcome, document, cardsFlyIn, negotiation, escrow, shipment, compliance, celebration }

/// Content for a single onboarding page — purely presentational data, no business logic.
/// [ctaLabel] is only set on the final page of a flow (e.g. "Start Trading").
class OnboardingPageData {
  final String emoji;
  final String title;
  final String description;
  final IconData icon;
  final OnboardingSceneType scene;
  final String? highlight;
  final String? ctaLabel;
  final IconData sceneIcon; // the moving/central icon a scene widget animates (plane/ship/truck/etc.)

  const OnboardingPageData({
    required this.emoji,
    required this.title,
    required this.description,
    required this.icon,
    required this.scene,
    this.highlight,
    this.ctaLabel,
    this.sceneIcon = Icons.flight,
  });
}
