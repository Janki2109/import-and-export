import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../models/order.dart';
import '../../services/admin_service.dart';
import '../../services/order_service.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/admin_ui_kit.dart';

/// Admin-wide Shipment Management — every shipment on the platform with status filter,
/// search, and a tracking-timeline detail view. Backed by the admin-only GET /admin/shipments
/// endpoint; the timeline itself reuses the existing /shipments/:id/timeline endpoint.
class AdminShipmentScreen extends StatefulWidget {
  const AdminShipmentScreen({super.key});
  @override
  State<AdminShipmentScreen> createState() => _AdminShipmentScreenState();
}

class _AdminShipmentScreenState extends State<AdminShipmentScreen> {
  final _service = AdminService();
  final _orderService = OrderService();
  late Future<List<AdminShipmentRow>> _future;
  String _query = '';
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _future = _service.listAllShipments();
  }

  void _refresh() => setState(() => _future = _service.listAllShipments());

  void _showTrack(AdminShipmentRow s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) => FutureBuilder<List<ShipmentEvent>>(
          future: _orderService.getTimeline(s.id),
          builder: (context, snapshot) {
            final events = snapshot.data ?? [];
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: [
                Text('${s.orderNumber} · Tracking', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 4),
                Text(s.trackingNumber ?? 'No tracking number', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                const SizedBox(height: 14),
                _row('Importer', s.importerName),
                _row('Exporter', s.exporterName),
                if (s.logisticsName != null) _row('Logistics Partner', s.logisticsName!),
                if (s.carrierName != null) _row('Carrier', s.carrierName!),
                _row('Status', statusLabel(s.status)),
                if (s.estimatedDelivery != null) _row('ETA', s.estimatedDelivery!.toLocal().toString().split(' ').first),
                const SizedBox(height: 14),
                const Text('Timeline', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 10),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                else if (events.isEmpty)
                  const Text('No tracking events yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5))
                else
                  ...events.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 5, right: 10), decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(statusLabel(e.status), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                  Text('${e.createdAt.toLocal().toString().split('.').first}${e.location != null ? ' · ${e.location}' : ''}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                  if (e.remarks != null && e.remarks!.isNotEmpty) Text(e.remarks!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
      appBar: const AdminGradientAppBar(title: 'Shipment Management'),
      body: AdminPageBackground(child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminShipmentRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final all = snapshot.data ?? [];
            final statuses = all.map((s) => s.status).toSet().toList()..sort();
            final filtered = all.where((s) {
              if (_statusFilter != null && s.status != _statusFilter) return false;
              if (_query.trim().isNotEmpty) {
                final q = _query.trim().toLowerCase();
                if (!s.orderNumber.toLowerCase().contains(q) && !(s.trackingNumber ?? '').toLowerCase().contains(q) && !s.importerName.toLowerCase().contains(q) && !s.exporterName.toLowerCase().contains(q)) return false;
              }
              return true;
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: AdminSearchField(
                    hint: 'Search by order #, tracking #, importer, exporter',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _chip('All', _statusFilter == null, () => setState(() => _statusFilter = null)),
                      const SizedBox(width: 6),
                      ...statuses.map((s) => Padding(padding: const EdgeInsets.only(right: 6), child: _chip(statusLabel(s), _statusFilter == s, () => setState(() => _statusFilter = _statusFilter == s ? null : s)))),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: filtered.isEmpty
                      ? const AdminEmptyState(icon: Icons.local_shipping_outlined, title: 'No shipments found.', subtitle: 'Try a different search or status filter.')
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final s = filtered[i];
                            return AdminReveal(
                              index: i,
                              child: AdminCard(
                                accent: const Color(0xFF0EA5E9),
                                onTap: () => _showTrack(s),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text(s.orderNumber, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                          StatusBadge(status: s.status),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text('${s.importerName} → ${s.exporterName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${s.trackingNumber ?? 'No tracking #'}${s.carrierName != null ? ' · ${s.carrierName}' : ''}',
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                                      ),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: () => _showTrack(s),
                                          style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                          icon: const Icon(Icons.route_outlined, size: 15),
                                          label: const Text('Track'),
                                        ),
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
