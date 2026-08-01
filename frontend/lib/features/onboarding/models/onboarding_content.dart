import 'package:flutter/material.dart';
import '../../../models/user.dart';
import 'onboarding_page_data.dart';

/// The three role-specific onboarding stories. Admin has no entry here by design — callers
/// (AppGuidePrefs / OnboardingFlowScreen) must never build a flow for UserRole.admin.
class OnboardingContent {
  static List<OnboardingPageData> forRole(UserRole role) {
    switch (role) {
      case UserRole.importer:
        return importer;
      case UserRole.exporter:
        return exporter;
      case UserRole.logistics:
        return logistics;
      case UserRole.admin:
        return const []; // never shown — router/settings gate this before it's reached
    }
  }

  static const importer = <OnboardingPageData>[
    OnboardingPageData(
      emoji: '🌍',
      title: 'Welcome to One Bharat',
      description: 'A world of trusted exporters, secured trade, and global reach — all in your pocket.',
      icon: Icons.public,
      scene: OnboardingSceneType.welcome,
    ),
    OnboardingPageData(
      emoji: '📄',
      title: 'Create Your RFQ',
      description: 'Post exactly what you need — product, quantity, destination — and let verified exporters come to you.',
      icon: Icons.request_quote_outlined,
      scene: OnboardingSceneType.document,
      sceneIcon: Icons.request_quote_outlined,
      highlight: 'RFQ Creation',
    ),
    OnboardingPageData(
      emoji: '🤝',
      title: 'Receive Quotations',
      description: 'Verified exporters compete for your business. Compare offers side by side, in real time.',
      icon: Icons.description_outlined,
      scene: OnboardingSceneType.cardsFlyIn,
      highlight: 'Quotation Screen',
    ),
    OnboardingPageData(
      emoji: '💬',
      title: 'Negotiate',
      description: 'Discuss price, quantity, Incoterms, and delivery — round by round — until both sides are happy.',
      icon: Icons.handshake_outlined,
      scene: OnboardingSceneType.negotiation,
      highlight: 'Negotiation Timeline',
    ),
    OnboardingPageData(
      emoji: '💳',
      title: 'Secure Escrow',
      description: 'Your payment sits safely in escrow and releases only as agreed milestones are met.',
      icon: Icons.account_balance_wallet_outlined,
      scene: OnboardingSceneType.escrow,
      highlight: 'Escrow',
    ),
    OnboardingPageData(
      emoji: '🚢',
      title: 'Global Shipment',
      description: 'By air, sea, or road — track your cargo live as it moves from origin to your door.',
      icon: Icons.local_shipping_outlined,
      scene: OnboardingSceneType.shipment,
      highlight: 'Shipment Tracking',
    ),
    OnboardingPageData(
      emoji: '📑',
      title: 'Compliance Center',
      description: 'Upload the required trade documents and clear compliance before your shipment departs.',
      icon: Icons.fact_check_outlined,
      scene: OnboardingSceneType.compliance,
      highlight: 'Compliance Center',
    ),
    OnboardingPageData(
      emoji: '🎉',
      title: "You're Ready",
      description: 'Everything you need for secure, global trade is right here. Let\'s get started.',
      icon: Icons.rocket_launch_outlined,
      scene: OnboardingSceneType.celebration,
      ctaLabel: 'Start Trading',
    ),
  ];

  static const exporter = <OnboardingPageData>[
    OnboardingPageData(
      emoji: '🌍',
      title: 'Welcome to One Bharat',
      description: 'Reach verified importers worldwide and grow your export business with secure, escrow-backed trade.',
      icon: Icons.public,
      scene: OnboardingSceneType.welcome,
    ),
    OnboardingPageData(
      emoji: '🔎',
      title: 'Browse RFQs',
      description: 'Discover live buy requests from importers looking for exactly what you supply.',
      icon: Icons.travel_explore_outlined,
      scene: OnboardingSceneType.cardsFlyIn,
      highlight: 'Browse RFQs',
    ),
    OnboardingPageData(
      emoji: '📝',
      title: 'Submit Quote',
      description: 'Respond with your price, quantity and delivery terms — built and sent in seconds.',
      icon: Icons.description_outlined,
      scene: OnboardingSceneType.document,
      sceneIcon: Icons.description_outlined,
      highlight: 'Submit Quotation',
    ),
    OnboardingPageData(
      emoji: '💬',
      title: 'Negotiate',
      description: 'Work out price, Incoterms, payment terms and delivery schedule directly with the importer.',
      icon: Icons.handshake_outlined,
      scene: OnboardingSceneType.negotiation,
      highlight: 'Negotiation Timeline',
    ),
    OnboardingPageData(
      emoji: '💰',
      title: 'Receive Escrow',
      description: 'Get paid safely — funds are held in escrow and released to your wallet as milestones are met.',
      icon: Icons.account_balance_wallet_outlined,
      scene: OnboardingSceneType.escrow,
      highlight: 'Escrow',
    ),
    OnboardingPageData(
      emoji: '📑',
      title: 'Upload Documents',
      description: 'Submit invoices, certificates and other trade documents required before shipment.',
      icon: Icons.fact_check_outlined,
      scene: OnboardingSceneType.compliance,
      highlight: 'Compliance Center',
    ),
    OnboardingPageData(
      emoji: '🚢',
      title: 'Ship Goods',
      description: 'Coordinate with your logistics partner and track the shipment through to delivery.',
      icon: Icons.local_shipping_outlined,
      scene: OnboardingSceneType.shipment,
      highlight: 'Shipment Tracking',
    ),
    OnboardingPageData(
      emoji: '🎉',
      title: 'Complete Order',
      description: 'Delivery confirmed, escrow released — straight to your wallet. That\'s trade, simplified.',
      icon: Icons.task_alt_outlined,
      scene: OnboardingSceneType.celebration,
      ctaLabel: 'Start Trading',
    ),
  ];

  static const logistics = <OnboardingPageData>[
    OnboardingPageData(
      emoji: '🌍',
      title: 'Welcome to One Bharat',
      description: 'Manage assigned shipments and keep every trade moving from pickup to delivery.',
      icon: Icons.public,
      scene: OnboardingSceneType.welcome,
    ),
    OnboardingPageData(
      emoji: '📦',
      title: 'Receive Shipment',
      description: 'You\'ll be notified the moment a new shipment is assigned to you.',
      icon: Icons.notifications_active_outlined,
      scene: OnboardingSceneType.cardsFlyIn,
      highlight: 'Shipment Assignment',
    ),
    OnboardingPageData(
      emoji: '✅',
      title: 'Accept Assignment',
      description: 'Review the shipment details and confirm you can carry it.',
      icon: Icons.assignment_turned_in_outlined,
      scene: OnboardingSceneType.document,
      sceneIcon: Icons.assignment_turned_in_outlined,
      highlight: 'Accept Assignment',
    ),
    OnboardingPageData(
      emoji: '🚚',
      title: 'Pickup Goods',
      description: 'Collect the goods from the exporter and mark pickup complete.',
      icon: Icons.inventory_2_outlined,
      scene: OnboardingSceneType.shipment,
      sceneIcon: Icons.local_shipping_outlined,
      highlight: 'Pickup Goods',
    ),
    OnboardingPageData(
      emoji: '📍',
      title: 'Update Tracking',
      description: 'Keep both the importer and exporter informed with real-time status updates.',
      icon: Icons.route_outlined,
      scene: OnboardingSceneType.shipment,
      sceneIcon: Icons.local_shipping_outlined,
      highlight: 'Shipment Tracking',
    ),
    OnboardingPageData(
      emoji: '📑',
      title: 'Upload Documents',
      description: 'Attach the bill of lading, airway bill, and any other required transport documents.',
      icon: Icons.upload_file_outlined,
      scene: OnboardingSceneType.compliance,
      highlight: 'Transport Documents',
    ),
    OnboardingPageData(
      emoji: '🎉',
      title: 'Deliver Successfully',
      description: 'Confirm final delivery so the importer can release the escrow payment.',
      icon: Icons.task_alt_outlined,
      scene: OnboardingSceneType.celebration,
      ctaLabel: 'Start Trading',
    ),
  ];
}
