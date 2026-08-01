import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/platform.dart';
import '../../services/platform_service.dart';

/// Shows disputes I've raised. Raising a new dispute happens from the order list
/// (see [showRaiseDisputeDialog]) since it needs the order's context.
class DisputesScreen extends StatefulWidget {
  const DisputesScreen({super.key});
  @override
  State<DisputesScreen> createState() => _DisputesScreenState();
}

class _DisputesScreenState extends State<DisputesScreen> {
  final _disputeService = DisputeService();
  late Future<List<Dispute>> _future;

  @override
  void initState() {
    super.initState();
    _future = _disputeService.listMine();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Disputes')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = _disputeService.listMine()),
        child: FutureBuilder<List<Dispute>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final disputes = snapshot.data ?? [];
            if (disputes.isEmpty) {
              return const Center(child: Text('No disputes raised.', style: TextStyle(color: AppColors.textSecondary)));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: disputes.length,
              itemBuilder: (context, i) {
                final d = disputes[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(d.reason),
                    subtitle: d.resolutionNotes != null ? Text('Resolution: ${d.resolutionNotes}') : Text('Order ${d.orderId.substring(0, 8)}'),
                    trailing: Chip(
                      label: Text(d.status),
                      backgroundColor: (d.status == 'open' ? AppColors.warning : AppColors.success).withValues(alpha: 0.12),
                      labelStyle: TextStyle(color: d.status == 'open' ? AppColors.warning : AppColors.success),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Reusable dialog: raise a dispute against a specific order. Call from any order-list screen.
Future<void> showRaiseDisputeDialog(BuildContext context, String orderId) async {
  final reasonCtrl = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Raise a Dispute'),
      content: TextField(
        controller: reasonCtrl,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'What went wrong?'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
      ],
    ),
  );
  if (confirmed != true || reasonCtrl.text.trim().isEmpty) return;

  try {
    await DisputeService().raise(orderId: orderId, reason: reasonCtrl.text.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispute raised. Escrow is frozen pending review.'), backgroundColor: AppColors.warning),
      );
    }
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
  }
}
