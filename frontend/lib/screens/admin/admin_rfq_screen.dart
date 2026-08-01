import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';
import '../../widgets/status_badge.dart';

/// Admin-wide RFQ Management — every RFQ on the platform, with search/status filter and
/// delete. Backed by the admin-only GET/DELETE /admin/rfqs endpoints added for this screen.
class AdminRFQScreen extends StatefulWidget {
  const AdminRFQScreen({super.key});
  @override
  State<AdminRFQScreen> createState() => _AdminRFQScreenState();
}

class _AdminRFQScreenState extends State<AdminRFQScreen> {
  final _service = AdminService();
  late Future<List<AdminRFQRow>> _future;
  String _query = '';
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _future = _service.listAllRFQs();
  }

  void _refresh() => setState(() => _future = _service.listAllRFQs());

  Future<void> _delete(AdminRFQRow rfq) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete RFQ'),
        content: Text('Delete ${rfq.rfqNumber}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteRFQ(rfq.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('RFQ deleted'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  void _showDetails(AdminRFQRow rfq) {
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
              Text(rfq.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 14),
              _row('RFQ Number', rfq.rfqNumber),
              _row('Importer', rfq.importerName),
              if (rfq.hsnCode != null) _row('HS Code', rfq.hsnCode!),
              _row('Quantity', '${rfq.quantity} ${rfq.unit}'),
              _row('Destination', rfq.destinationCountry),
              if (rfq.targetPrice != null) _row('Target Price', '₹${rfq.targetPrice!.toStringAsFixed(2)}/unit'),
              _row('Status', rfq.status),
              _row('Created', rfq.createdAt.toLocal().toString().split(' ').first),
              if (rfq.description != null && rfq.description!.isNotEmpty) _row('Description', rfq.description!),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RFQ Management')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminRFQRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final all = snapshot.data ?? [];
            final statuses = all.map((r) => r.status).toSet().toList()..sort();
            final filtered = all.where((r) {
              if (_statusFilter != null && r.status != _statusFilter) return false;
              if (_query.trim().isNotEmpty) {
                final q = _query.trim().toLowerCase();
                if (!r.productName.toLowerCase().contains(q) && !r.rfqNumber.toLowerCase().contains(q) && !r.importerName.toLowerCase().contains(q)) return false;
              }
              return true;
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search by RFQ #, product, or importer',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Theme.of(context).cardTheme.color,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
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
                      ? const Center(child: Text('No RFQs found.', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final rfq = filtered[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardTheme.color,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => _showDetails(rfq),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text(rfq.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                          StatusBadge(status: rfq.status),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text('${rfq.rfqNumber} · ${rfq.importerName} · ${rfq.destinationCountry}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text('Qty ${rfq.quantity} ${rfq.unit} · ${rfq.createdAt.toLocal().toString().split(' ').first}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _showDetails(rfq),
                                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                              icon: const Icon(Icons.visibility_outlined, size: 15),
                                              label: const Text('View'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _delete(rfq),
                                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                                              icon: const Icon(Icons.delete_outline, size: 15),
                                              label: const Text('Delete'),
                                            ),
                                          ),
                                        ],
                                      ),
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
