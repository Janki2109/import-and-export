import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/payment_terms.dart';
import '../../services/payment_terms_service.dart';
import '../../widgets/admin_ui_kit.dart';

const _paymentModelFilters = [null, 'advance_100', 'advance_balance', 'milestone_escrow', 'letter_of_credit', 'open_account', 'custom'];
const _paymentModelLabels = {
  null: 'All',
  'advance_100': '100% Advance',
  'advance_balance': 'Advance + Balance',
  'milestone_escrow': 'Milestone Escrow',
  'letter_of_credit': 'Letter of Credit',
  'open_account': 'Open Account',
  'custom': 'Custom',
};

/// Admin Payment Management — additive admin module. Dashboard cards, filterable list of
/// every order's payment schedule, and a link into each order's milestone timeline (the
/// same "Payment Schedule" section rendered on the order details screen owns the actual
/// approve/reject/hold/release actions, so this list purely browses + navigates).
class AdminPaymentScreen extends StatefulWidget {
  const AdminPaymentScreen({super.key});
  @override
  State<AdminPaymentScreen> createState() => _AdminPaymentScreenState();
}

class _AdminPaymentScreenState extends State<AdminPaymentScreen> {
  final _service = PaymentTermsService();
  late Future<List<AdminPaymentRow>> _future;
  late Future<AdminPaymentSummary> _summaryFuture;
  String? _modelFilter;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _service.adminList();
    _summaryFuture = _service.adminSummary();
  }

  void _refresh() => setState(() {
        _future = _service.adminList(paymentModel: _modelFilter);
        _summaryFuture = _service.adminSummary();
      });

  Color _statusColor(String status) => status == 'completed' ? AppColors.success : AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdminGradientAppBar(title: 'Payment Management'),
      body: AdminPageBackground(
        child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FutureBuilder<AdminPaymentSummary>(
              future: _summaryFuture,
              builder: (context, snapshot) {
                final s = snapshot.data;
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.8,
                  children: [
                    AdminReveal(index: 0, child: _summaryCard('Total in Escrow', s == null ? '—' : '₹${s.totalEscrow.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined, AppColors.primary)),
                    AdminReveal(index: 1, child: _summaryCard('Pending Releases', '${s?.pendingReleases ?? '—'}', Icons.hourglass_top_outlined, AppColors.warning)),
                    AdminReveal(index: 2, child: _summaryCard('Released', s == null ? '—' : '₹${s.released.toStringAsFixed(0)}', Icons.verified_outlined, AppColors.success)),
                    AdminReveal(index: 3, child: _summaryCard('Upcoming Milestones', '${s?.upcomingMilestones ?? '—'}', Icons.schedule_outlined, AppColors.heldBlue)),
                    AdminReveal(index: 4, child: _summaryCard('Delayed / On Hold', '${s?.delayedMilestones ?? '—'}', Icons.block, AppColors.error)),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            AdminSearchField(
              hint: 'Search by order #, product, importer, exporter',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _paymentModelFilters
                    .map((m) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(_paymentModelLabels[m]!, style: TextStyle(fontSize: 12, color: _modelFilter == m ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600)),
                            selected: _modelFilter == m,
                            onSelected: (_) {
                              setState(() => _modelFilter = m);
                              _refresh();
                            },
                            selectedColor: AppColors.primary,
                            backgroundColor: Theme.of(context).cardTheme.color,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<AdminPaymentRow>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) {
                  return Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
                }
                var rows = snapshot.data ?? [];
                if (_query.trim().isNotEmpty) {
                  final q = _query.trim().toLowerCase();
                  rows = rows.where((r) =>
                      r.orderNumber.toLowerCase().contains(q) ||
                      r.productName.toLowerCase().contains(q) ||
                      r.importerName.toLowerCase().contains(q) ||
                      r.exporterName.toLowerCase().contains(q)).toList();
                }
                if (rows.isEmpty) {
                  return const AdminEmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'No payment schedules found',
                    subtitle: 'Try adjusting your search or filter.',
                  );
                }
                return Column(
                  children: rows.asMap().entries.map((entry) {
                    final i = entry.key;
                    final row = entry.value;
                    final color = _statusColor(row.status);
                    return AdminReveal(
                      index: i,
                      child: AdminCard(
                        accent: const Color(0xFF16A34A),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(row.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                AdminStatusBadge(label: row.status.toUpperCase(), color: color),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('${row.orderNumber} · ${_paymentModelLabels[row.paymentModel] ?? row.paymentModel}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                            const SizedBox(height: 4),
                            Text('${row.importerName} ← ${row.exporterName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('${row.currency} ${row.totalAmount.toStringAsFixed(2)} · ${row.releasedCount}/${row.milestoneCount} milestones released', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const Spacer(),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
          Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
