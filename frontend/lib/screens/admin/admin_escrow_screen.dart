import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';
import '../../widgets/status_badge.dart';

/// Admin Escrow Wallet — every order with a payment (self-declared via UPI, held in escrow
/// until release), with the three direct admin actions the workflow requires: Release, Hold,
/// Refund — independent of the dispute-resolution path (DisputeService.Resolve), which still
/// exists separately for disputed orders.
class AdminEscrowScreen extends StatefulWidget {
  const AdminEscrowScreen({super.key});
  @override
  State<AdminEscrowScreen> createState() => _AdminEscrowScreenState();
}

class _AdminEscrowScreenState extends State<AdminEscrowScreen> {
  final _adminService = AdminService();
  late Future<(EscrowSummary, List<EscrowOrderRow>)> _future;
  String? _statusFilter;
  bool _busy = false;

  static const _filters = ['All', 'held', 'on_hold', 'released', 'refunded'];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(EscrowSummary, List<EscrowOrderRow>)> _load() async {
    final results = await Future.wait([
      _adminService.getEscrowSummary(),
      _adminService.listEscrowOrders(status: _statusFilter),
    ]);
    return (results[0] as EscrowSummary, results[1] as List<EscrowOrderRow>);
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _release(EscrowOrderRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Payment'),
        content: Text('Release ₹${row.payoutAmount.toStringAsFixed(2)} from escrow to ${row.exporterName} for order ${row.orderNumber}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Release')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runAction(() => _adminService.releaseEscrowPayment(row.orderId), 'Payment released to exporter');
  }

  Future<void> _hold(EscrowOrderRow row) async {
    await _runAction(() => _adminService.holdEscrowPayment(row.orderId), 'Payment placed on hold');
  }

  Future<void> _refund(EscrowOrderRow row) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund Payment'),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    if (confirmed != true || reasonCtrl.text.trim().isEmpty) return;
    await _runAction(() => _adminService.refundEscrowPayment(row.orderId, reasonCtrl.text.trim()), 'Payment refunded to importer');
  }

  Future<void> _showHistory(EscrowOrderRow row) async {
    final history = await _adminService.getEscrowHistory(row.orderId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Escrow History — ${row.orderNumber}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 12),
              Expanded(
                child: history.isEmpty
                    ? const Center(child: Text('No audit entries yet.', style: TextStyle(color: AppColors.textSecondary)))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: history.length,
                        itemBuilder: (context, i) {
                          final h = history[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.history, color: AppColors.primary),
                              title: Text(_actionLabel(h['action'] ?? '')),
                              subtitle: Text((h['created_at'] ?? '').toString().split('.').first.replaceFirst('T', ' ')),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'escrow.payment_received':
        return 'Payment Received';
      case 'escrow.hold':
        return 'Held by Admin';
      case 'escrow.released':
        return 'Released — Wallet Credited';
      case 'escrow.refunded':
        return 'Refunded to Importer';
      default:
        return action;
    }
  }

  Future<void> _runAction(Future<void> Function() action, String successMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage), backgroundColor: AppColors.success));
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escrow Payments')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<(EscrowSummary, List<EscrowOrderRow>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final (summary, rows) = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryGrid(summary: summary),
                const SizedBox(height: 16),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final f = _filters[i];
                      final selected = (f == 'All' && _statusFilter == null) || f == _statusFilter;
                      return ChoiceChip(
                        label: Text(f == 'All' ? 'All' : statusLabel(f)),
                        selected: selected,
                        onSelected: (_) => setState(() {
                          _statusFilter = f == 'All' ? null : f;
                          _future = _load();
                        }),
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('No escrow orders match this filter.', style: TextStyle(color: AppColors.textSecondary))),
                  )
                else
                  ...rows.map((row) => _EscrowCard(
                        row: row,
                        busy: _busy,
                        onRelease: () => _release(row),
                        onHold: () => _hold(row),
                        onRefund: () => _refund(row),
                        onHistory: () => _showHistory(row),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final EscrowSummary summary;
  const _SummaryGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: [
        _card('Escrow Balance', summary.holdingBalance, Icons.account_balance_outlined, AppColors.primary),
        _card('Pending Release', summary.pendingRelease, Icons.hourglass_top_outlined, AppColors.warning),
        _card('Released Payments', summary.totalReleased, Icons.check_circle_outline, AppColors.success),
        _card('Refunded Payments', summary.totalRefunded, Icons.replay_outlined, AppColors.error),
      ],
    );
  }

  Widget _card(String label, double value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 15, color: color), const SizedBox(width: 6), Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis))]),
            const Spacer(),
            Text('₹${value.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
          ],
        ),
      ),
    );
  }
}

class _EscrowCard extends StatelessWidget {
  final EscrowOrderRow row;
  final bool busy;
  final VoidCallback onRelease;
  final VoidCallback onHold;
  final VoidCallback onRefund;
  final VoidCallback onHistory;
  const _EscrowCard({required this.row, required this.busy, required this.onRelease, required this.onHold, required this.onRefund, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    final canAct = row.escrowStatus == 'held' || row.escrowStatus == 'on_hold';
    final now = DateTime.now();
    final dueSoon = row.escrowStatus == 'held' && row.releaseDueAt != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(row.orderNumber, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                IconButton(icon: const Icon(Icons.history, size: 20), tooltip: 'Escrow History', onPressed: onHistory, visualDensity: VisualDensity.compact),
                StatusBadge(status: row.escrowStatus),
              ],
            ),
            const SizedBox(height: 8),
            _kv('Importer', row.importerName),
            _kv('Exporter', row.exporterName),
            _kv('Order Amount', '₹${row.orderAmount.toStringAsFixed(2)}'),
            _kv('Payout Amount', '₹${row.payoutAmount.toStringAsFixed(2)}'),
            Row(
              children: [
                const Expanded(child: Text('Shipment Status', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
                StatusBadge(status: row.orderStatus),
              ],
            ),
            if (dueSoon) ...[
              const SizedBox(height: 8),
              Text(
                row.releaseDueAt!.isBefore(now)
                    ? 'Awaiting Buyer Confirmation — Auto Release Overdue'
                    : 'Awaiting Buyer Confirmation — Auto Release Due In ${row.releaseDueAt!.difference(now).inDays} Day${row.releaseDueAt!.difference(now).inDays == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.warning, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ],
            if (row.hasOpenDispute) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Dispute Open — Payment Locked. Resolve the dispute before releasing payment.',
                          style: TextStyle(color: AppColors.error, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
            if (canAct) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : onHold,
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning),
                      child: Text(row.escrowStatus == 'on_hold' ? 'On Hold' : 'Hold'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : onRefund,
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                      child: const Text('Refund'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (busy || row.hasOpenDispute) ? null : onRelease,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                      child: const Text('Release'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        ],
      ),
    );
  }
}
