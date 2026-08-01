import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';

const _roleTabs = [
  (null, 'All'),
  ('importer', 'Importer'),
  ('exporter', 'Exporter'),
  ('admin', 'Admin'),
];

/// Wallet Management — every user's wallet (importer/exporter/admin) at a glance:
/// balance, pending release, released, and lifetime withdrawn. Backed by the new
/// GET /admin/wallets endpoint (a read-only aggregate over the existing ledger — no
/// change to wallet balance logic).
class AdminWalletScreen extends StatefulWidget {
  const AdminWalletScreen({super.key});
  @override
  State<AdminWalletScreen> createState() => _AdminWalletScreenState();
}

class _AdminWalletScreenState extends State<AdminWalletScreen> with SingleTickerProviderStateMixin {
  final _adminService = AdminService();
  late TabController _tabController;
  late Future<List<AdminWalletRow>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _roleTabs.length, vsync: this);
    _future = _adminService.listWallets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _future = _adminService.listWallets());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet Management'),
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: _roleTabs.map((t) => Tab(text: t.$2)).toList(), onTap: (_) => setState(() {})),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminWalletRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final all = snapshot.data ?? [];
            final roleFilter = _roleTabs[_tabController.index].$1;
            var filtered = roleFilter == null ? all : all.where((w) => w.role == roleFilter).toList();
            if (_query.trim().isNotEmpty) {
              final q = _query.trim().toLowerCase();
              filtered = filtered.where((w) => w.fullName.toLowerCase().contains(q)).toList();
            }

            final totalBalance = all.fold<double>(0, (s, w) => s + w.balance);
            final totalPending = all.fold<double>(0, (s, w) => s + w.pendingRelease);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(child: _summaryCard('Total Balance', totalBalance, AppColors.primary)),
                      const SizedBox(width: 10),
                      Expanded(child: _summaryCard('Pending Release', totalPending, AppColors.warning)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search by name',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Theme.of(context).cardTheme.color,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No wallets found.', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final w = filtered[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardTheme.color,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(radius: 18, backgroundColor: AppColors.primary.withValues(alpha: 0.12), child: Text(w.fullName.isNotEmpty ? w.fullName[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800))),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(w.fullName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                            Text(w.role.toUpperCase(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                                          ],
                                        ),
                                      ),
                                      Text('₹${w.balance.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.primary)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(child: _figure('Pending', w.pendingRelease, AppColors.warning)),
                                      Expanded(child: _figure('Released', w.totalReleased, AppColors.success)),
                                      Expanded(child: _figure('Withdrawn', w.totalWithdrawn, AppColors.error)),
                                    ],
                                  ),
                                ],
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

  Widget _summaryCard(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('₹${value.toStringAsFixed(0)}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17)),
        ],
      ),
    );
  }

  Widget _figure(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        const SizedBox(height: 2),
        Text('₹${value.toStringAsFixed(0)}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ],
    );
  }
}
