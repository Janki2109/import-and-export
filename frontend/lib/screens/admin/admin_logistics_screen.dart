import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';
import '../../widgets/admin_ui_kit.dart';

const Color _kLogisticsAccent = Color(0xFFEA580C);

/// Logistics Management — every logistics-role user with their company, fleet, and orders
/// assigned. Backed by the new GET /admin/logistics endpoint; Approve/Suspend reuses the
/// same is_active toggle User Management already uses. No rating is shown — nothing in the
/// schema collects one yet.
class AdminLogisticsScreen extends StatefulWidget {
  const AdminLogisticsScreen({super.key});
  @override
  State<AdminLogisticsScreen> createState() => _AdminLogisticsScreenState();
}

class _AdminLogisticsScreenState extends State<AdminLogisticsScreen> {
  final _adminService = AdminService();
  late Future<List<AdminLogisticsRow>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _adminService.listLogistics();
  }

  void _refresh() => setState(() => _future = _adminService.listLogistics());

  Future<void> _setActive(AdminLogisticsRow l, bool active) async {
    try {
      await _adminService.setUserActive(l.userId, active);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(active ? 'Partner approved' : 'Partner suspended'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  void _showDetails(AdminLogisticsRow l) {
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
              Text(l.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 14),
              _row('Company', l.companyName ?? '—'),
              _row('Email', l.email),
              _row('Phone', l.phone),
              _row('Country', l.country ?? '—'),
              _row('Fleet Size', '${l.fleetCount} vehicle(s)'),
              _row('Vehicle Types', l.vehicleTypes ?? '—'),
              _row('Orders Assigned', '${l.ordersAssigned}'),
              _row('Status', l.isActive ? 'Approved / Active' : 'Suspended'),
              _row('Registered', l.createdAt.toLocal().toString().split(' ').first),
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
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AdminGradientAppBar(title: 'Logistics Management'),
      body: AdminPageBackground(
        child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminLogisticsRow>>(
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
                : all.where((l) => l.fullName.toLowerCase().contains(_query.trim().toLowerCase()) || (l.companyName ?? '').toLowerCase().contains(_query.trim().toLowerCase())).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: AdminSearchField(
                    hint: 'Search by name or company',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const AdminEmptyState(
                          icon: Icons.local_shipping_outlined,
                          title: 'No partners found',
                          subtitle: 'No logistics partners match your search.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final l = filtered[i];
                            return AdminReveal(
                              index: i,
                              child: AdminCard(
                                onTap: () => _showDetails(l),
                                accent: _kLogisticsAccent,
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const AdminIconBadge(icon: Icons.local_shipping_outlined, color: _kLogisticsAccent, size: 40),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(l.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                Text(l.companyName ?? l.email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                              ],
                                            ),
                                          ),
                                          AdminStatusBadge(label: l.isActive ? 'Approved' : 'Suspended', color: l.isActive ? AppColors.success : AppColors.error),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          _tag(Icons.local_shipping_outlined, '${l.fleetCount} fleet'),
                                          _tag(Icons.inventory_2_outlined, '${l.ordersAssigned} orders'),
                                          if (l.country != null) _tag(Icons.public_outlined, l.country!),
                                          if (l.vehicleTypes != null) _tag(Icons.category_outlined, l.vehicleTypes!),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _showDetails(l),
                                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8)),
                                              icon: const Icon(Icons.visibility_outlined, size: 14),
                                              label: const Text('View', style: TextStyle(fontSize: 12)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _setActive(l, !l.isActive),
                                              style: OutlinedButton.styleFrom(
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                padding: const EdgeInsets.symmetric(vertical: 8),
                                                foregroundColor: l.isActive ? AppColors.warning : AppColors.success,
                                              ),
                                              icon: Icon(l.isActive ? Icons.pause_circle_outline : Icons.check_circle_outline, size: 14),
                                              label: Text(l.isActive ? 'Suspend' : 'Approve', style: const TextStyle(fontSize: 12)),
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
        ),
      ),
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
