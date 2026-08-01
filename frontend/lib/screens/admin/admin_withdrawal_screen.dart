import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';

/// Withdrawal Requests — every withdrawal debit from the ledger, with Approve (mark as
/// paid — a pure audit-reference update) and Reject (refunds the amount back to the user's
/// wallet via a new credit ledger entry, same append-only pattern every other credit in
/// this app already uses). Neither action touches WalletService.Withdraw's own balance math.
///
/// Note: the schema has no bank-account field anywhere (withdrawals are UPI self-declared,
/// same as escrow payments), so a "Bank" column isn't shown — only what's real.
class AdminWithdrawalScreen extends StatefulWidget {
  const AdminWithdrawalScreen({super.key});
  @override
  State<AdminWithdrawalScreen> createState() => _AdminWithdrawalScreenState();
}

class _AdminWithdrawalScreenState extends State<AdminWithdrawalScreen> {
  final _adminService = AdminService();
  late Future<List<AdminWithdrawalRow>> _future;
  String? _statusFilter = 'pending';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _adminService.listWithdrawals();
  }

  void _refresh() => setState(() => _future = _adminService.listWithdrawals());

  Future<void> _approve(AdminWithdrawalRow w) async {
    setState(() => _busy = true);
    try {
      await _adminService.approveWithdrawal(w.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as paid'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(AdminWithdrawalRow w) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reject Withdrawal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('₹${w.amount.toStringAsFixed(2)} will be refunded back to ${w.userName}\'s wallet.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            const SizedBox(height: 12),
            TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject & Refund')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _adminService.rejectWithdrawal(w.id, reasonCtrl.text.trim().isEmpty ? 'Rejected by admin' : reasonCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Withdrawal rejected and refunded'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showDetails(AdminWithdrawalRow w) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(w.userName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 14),
              _row('Amount', '₹${w.amount.toStringAsFixed(2)}'),
              _row('Role', w.role),
              _row('Requested', w.createdAt.toLocal().toString().split('.').first),
              _row('Reference', w.referenceId ?? '—'),
              _row('Status', w.status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return AppColors.warning;
      case 'paid':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Withdrawal Requests')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminWithdrawalRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final all = snapshot.data ?? [];
            final filtered = _statusFilter == null ? all : all.where((w) => w.status == _statusFilter).toList();
            final pendingCount = all.where((w) => w.status == 'pending').length;

            return Column(
              children: [
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    children: [
                      _chip('Pending ($pendingCount)', _statusFilter == 'pending', () => setState(() => _statusFilter = 'pending')),
                      const SizedBox(width: 6),
                      _chip('Paid', _statusFilter == 'paid', () => setState(() => _statusFilter = 'paid')),
                      const SizedBox(width: 6),
                      _chip('Rejected', _statusFilter == 'rejected', () => setState(() => _statusFilter = 'rejected')),
                      const SizedBox(width: 6),
                      _chip('All', _statusFilter == null, () => setState(() => _statusFilter = null)),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No withdrawal requests here.', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final w = filtered[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardTheme.color,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => _showDetails(w),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(w.userName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                                Text(w.role.toUpperCase(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                                              ],
                                            ),
                                          ),
                                          Text('₹${w.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                            decoration: BoxDecoration(color: _statusColor(w.status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                            child: Text(w.status.toUpperCase(), style: TextStyle(color: _statusColor(w.status), fontSize: 10, fontWeight: FontWeight.w700)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(w.createdAt.toLocal().toString().split(' ').first, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                        ],
                                      ),
                                      if (w.status == 'pending') ...[
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: _busy ? null : () => _reject(w),
                                                style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                                                icon: const Icon(Icons.close, size: 16),
                                                label: const Text('Reject'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: _busy ? null : () => _approve(w),
                                                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), backgroundColor: AppColors.success),
                                                icon: const Icon(Icons.check, size: 16),
                                                label: const Text('Approve'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
    );
  }
}
