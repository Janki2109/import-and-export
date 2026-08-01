import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../models/platform.dart';
import '../../services/platform_service.dart';
import 'api_keys_screen.dart';

/// Premium/Featured legacy add-ons plus the Free/Silver/Gold/Enterprise subscription
/// tiers — paid via a upi://pay deep link (opens GPay/PhonePe/etc), then self-declared
/// "Payment Done" once the user returns to the app. No payment gateway involved.
class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});
  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  final _membershipService = MembershipService();
  Future<Membership>? _future;

  @override
  void initState() {
    super.initState();
    _future = _membershipService.getMine();
  }

  bool _isTier(String type) => ['silver', 'gold', 'enterprise'].contains(type);

  Future<void> _startPurchase(String type) async {
    try {
      final order = switch (type) {
        'premium' => await _membershipService.createPremiumOrder(),
        'featured' => await _membershipService.createFeaturedOrder(),
        _ => await _membershipService.createTierOrder(type),
      };
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isDismissible: false,
        builder: (ctx) => _PaymentSheet(
          amount: (order['amount'] as num).toDouble(),
          label: '${type[0].toUpperCase()}${type.substring(1)} subscription (30 days)',
          onLaunchUpi: () async {
            final uri = Uri.parse(order['upi_link']);
            final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (!ok && ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('No UPI app found. Install GPay, PhonePe, or another UPI app.')),
              );
            }
          },
          onPaymentDone: () async {
            Navigator.pop(ctx);
            await _confirmPurchase(type);
          },
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _confirmPurchase(String type) async {
    try {
      if (type == 'premium') {
        await _membershipService.verifyPremiumPayment();
      } else if (type == 'featured') {
        await _membershipService.verifyFeaturedPayment();
      } else if (_isTier(type)) {
        await _membershipService.verifyTierPayment(tier: type);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activated!'), backgroundColor: AppColors.success));
        setState(() => _future = _membershipService.getMine());
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Membership')),
      body: FutureBuilder<Membership>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final m = snapshot.data;
          final tier = m?.tier ?? 'free';
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current Tier: $tier'.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                    if (m?.isFeatured == true) const Padding(padding: EdgeInsets.only(top: 6), child: Text('★ Featured', style: TextStyle(color: Colors.white))),
                    if (m?.expiresAt != null)
                      Padding(padding: const EdgeInsets.only(top: 6), child: Text('Expires: ${m!.expiresAt!.toLocal().toString().split(' ').first}', style: const TextStyle(color: Colors.white70))),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Subscription Tiers', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _tierCard('silver', 'Silver', 'Unlimited RFQ', Icons.workspace_premium_outlined, tier),
              _tierCard('gold', 'Gold', 'Unlimited RFQ + priority search', Icons.star_outline, tier),
              _tierCard('enterprise', 'Enterprise', 'Everything + dedicated manager + API access', Icons.business_center_outlined, tier),
              if (tier == 'enterprise') ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.vpn_key_outlined, color: AppColors.primary),
                    title: const Text('Manage API Keys'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApiKeysScreen())),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text('Add-ons', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.star_outline, color: AppColors.accent),
                  title: const Text('Featured Placement'),
                  subtitle: const Text('Appear in "Featured Exporters/Logistics" — 30 days'),
                  trailing: ElevatedButton(onPressed: () => _startPurchase('featured'), child: const Text('Get Featured')),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tierCard(String tierId, String label, String subtitle, IconData icon, String currentTier) {
    final isCurrent = currentTier == tierId;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label),
        subtitle: Text(subtitle),
        trailing: isCurrent
            ? const Chip(label: Text('Active'), backgroundColor: AppColors.success, labelStyle: TextStyle(color: Colors.white))
            : ElevatedButton(onPressed: () => _startPurchase(tierId), child: const Text('Subscribe')),
      ),
    );
  }
}

/// Bottom sheet shown after a purchase order is created: "Pay via UPI" opens the user's UPI
/// app with the amount pre-filled; "Payment Done" self-declares the payment once they're back.
class _PaymentSheet extends StatelessWidget {
  final double amount;
  final String label;
  final VoidCallback onLaunchUpi;
  final VoidCallback onPaymentDone;

  const _PaymentSheet({
    required this.amount,
    required this.label,
    required this.onLaunchUpi,
    required this.onPaymentDone,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pay ₹$amount via UPI', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onLaunchUpi,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Pay via UPI App'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onPaymentDone,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Payment Done'),
            ),
          ],
        ),
      ),
    );
  }
}
