import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_export.dart';
import '../../services/admin_service.dart';
import '../../widgets/admin_ui_kit.dart';

const _tabs = [
  (null, 'All'),
  ('importer', 'Importers'),
  ('exporter', 'Exporters'),
  ('logistics', 'Logistics'),
  ('admin', 'Admins'),
];

/// User Management — tabbed by role, with company/country/GST/IEC/verification columns,
/// search, view/suspend/activate/delete, and CSV/PDF export. Backed by the new
/// GET /admin/users/rich + DELETE /admin/users/:id endpoints.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> with SingleTickerProviderStateMixin {
  final _adminService = AdminService();
  late TabController _tabController;
  late Future<List<AdminUserRow>> _future;
  String _query = '';
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    // BUG FIX: previously refreshed from a controller listener guarded by
    // `!indexIsChanging` — that guard's timing meant a tap could settle on the wrong
    // in-flight future, so every tab ended up showing the same (first-loaded) list.
    // TabBar's own `onTap` fires exactly once per tap, after `controller.index` has
    // already been updated to the tapped tab, so reading `_tabController.index` here is
    // always correct — no ambiguity, no missed/duplicate refreshes.
    _future = _adminService.listUsersRich(role: _tabs[_tabController.index].$1);
  }

  void _onTabTapped(int index) => _refresh();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _future = _adminService.listUsersRich(role: _tabs[_tabController.index].$1));

  Future<void> _setActive(AdminUserRow u, bool active) async {
    try {
      await _adminService.setUserActive(u.id, active);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(active ? 'User activated' : 'User suspended'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _delete(AdminUserRow u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete User'),
        content: Text('Delete ${u.fullName}? This only succeeds if the account has no orders, RFQs, or quotations — otherwise suspend it instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _adminService.deleteUser(u.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User deleted'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  void _showDetails(AdminUserRow u) {
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
              Row(children: [
                CircleAvatar(radius: 24, backgroundColor: AppColors.primary.withValues(alpha: 0.12), child: Text(u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 18))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(u.role.toUpperCase(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              _row('User ID', _displayId(u)),
              _row('Company', u.companyName ?? '—'),
              _row('Email', u.email),
              _row('Phone', u.phone),
              _row('Country', u.country ?? '—'),
              _row('GST Number', u.gstNumber ?? '—'),
              _row('IEC Code', u.iecCode ?? '—'),
              _row('Verification', u.kycStatus ?? 'Not submitted'),
              _row('Registered', u.createdAt.toLocal().toString().split(' ').first),
              _row('Status', u.isActive ? 'Active' : 'Suspended'),
            ],
          ),
        ),
      ),
    );
  }

  // Real user ID (the actual backend UUID), presented with a readable role prefix — the
  // prefix is derived from the user's real `role` field, not a separate invented ID scheme.
  String _displayId(AdminUserRow u) {
    final prefix = switch (u.role) {
      'importer' => 'IMP',
      'exporter' => 'EXP',
      'logistics' => 'LOG',
      'admin' => 'ADM',
      _ => u.role.toUpperCase(),
    };
    final short = u.id.length > 8 ? u.id.substring(0, 8).toUpperCase() : u.id.toUpperCase();
    return '$prefix-$short';
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }

  List<String> get _headers => ['Name', 'Role', 'Company', 'Email', 'Phone', 'Country', 'GST', 'IEC', 'Verification', 'Registered', 'Status'];

  List<String> _rowFor(AdminUserRow u) => [
        u.fullName,
        u.role,
        u.companyName ?? '',
        u.email,
        u.phone,
        u.country ?? '',
        u.gstNumber ?? '',
        u.iecCode ?? '',
        u.kycStatus ?? 'not submitted',
        u.createdAt.toLocal().toString().split(' ').first,
        u.isActive ? 'Active' : 'Suspended',
      ];

  Future<void> _export(List<AdminUserRow> users, String format) async {
    setState(() => _exporting = true);
    try {
      if (format == 'pdf') {
        final bytes = await buildAdminTablePdf(title: 'User Management', headers: _headers, rows: users.map(_rowFor).toList());
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'users.pdf');
      } else {
        final csv = buildAdminCsv(_headers, users.map(_rowFor).toList());
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/users.csv');
        await file.writeAsString(csv);
        await Share.shareXFiles([XFile(file.path)], text: 'User Management Export');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AdminGradientAppBar(
        title: 'User Management',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TabBar(
              controller: _tabController,
              onTap: _onTabTapped,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              // Explicit white/translucent-white styling — without this, TabBar falls back
              // to the theme's primary (blue) label color, which is invisible against this
              // same blue gradient AppBar background (the bug being fixed here).
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              indicator: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              splashBorderRadius: BorderRadius.circular(20),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              tabs: _tabs.map((t) => Tab(height: 38, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t.$2, maxLines: 1, overflow: TextOverflow.visible)))).toList(),
            ),
          ),
        ),
      ),
      body: AdminPageBackground(child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminUserRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final all = snapshot.data ?? [];
            final filtered = _query.trim().isEmpty
                ? all
                : all.where((u) {
                    final q = _query.trim().toLowerCase();
                    return u.fullName.toLowerCase().contains(q) || u.email.toLowerCase().contains(q) || (u.companyName ?? '').toLowerCase().contains(q);
                  }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: AdminSearchField(
                          hint: 'Search by name, email, or company',
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        enabled: !_exporting,
                        icon: _exporting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.file_download_outlined),
                        onSelected: (v) => _export(filtered, v),
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'excel', child: Text('Export Excel (CSV)')),
                          PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const AdminEmptyState(icon: Icons.people_outline, title: 'No users found.', subtitle: 'Try a different search or role tab.')
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final u = filtered[i];
                            return AdminReveal(
                              index: i,
                              child: AdminCard(
                                accent: const Color(0xFF7C3AED),
                                onTap: () => _showDetails(u),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          AdminIconBadge(icon: Icons.person, color: const Color(0xFF7C3AED), size: 40),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                Text(_displayId(u), style: const TextStyle(color: AppColors.primary, fontSize: 10.5, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                Text(u.companyName ?? u.email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                              ],
                                            ),
                                          ),
                                          AdminStatusBadge(label: u.isActive ? 'Active' : 'Suspended', color: u.isActive ? AppColors.success : AppColors.error),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          if (u.country != null) _tag(Icons.public_outlined, u.country!),
                                          if (u.gstNumber != null) _tag(Icons.receipt_long_outlined, 'GST ${u.gstNumber}'),
                                          if (u.iecCode != null) _tag(Icons.badge_outlined, 'IEC ${u.iecCode}'),
                                          _tag(u.kycStatus == 'approved' ? Icons.verified_outlined : Icons.hourglass_top_outlined, u.kycStatus ?? 'Not submitted'),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _showDetails(u),
                                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8)),
                                              icon: const Icon(Icons.visibility_outlined, size: 14),
                                              label: const Text('View', style: TextStyle(fontSize: 12)),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _setActive(u, !u.isActive),
                                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8), foregroundColor: u.isActive ? AppColors.warning : AppColors.success),
                                              icon: Icon(u.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 14),
                                              label: Text(u.isActive ? 'Suspend' : 'Activate', style: const TextStyle(fontSize: 12)),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _delete(u),
                                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8), foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                                              icon: const Icon(Icons.delete_outline, size: 14),
                                              label: const Text('Delete', style: TextStyle(fontSize: 12)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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
      )),
    );
  }

  Widget _tag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11.5, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
