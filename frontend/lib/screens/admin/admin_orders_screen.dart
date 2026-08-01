import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../models/order.dart';
import '../../models/trade.dart';
import '../../services/admin_export.dart';
import '../../services/admin_service.dart';
import '../../services/trade_service.dart';
import '../../widgets/status_badge.dart';
import '../shared/order_details_screen.dart';

/// Order Management — importer/exporter/logistics names plus escrow/payment/shipment
/// status in one row, invoice/document viewing, and CSV/PDF export. Backed by the new
/// GET /admin/orders/rich endpoint.
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});
  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  final _adminService = AdminService();
  final _tradeService = TradeService();
  late Future<List<AdminOrderRow>> _future;
  String _query = '';
  String? _statusFilter;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _future = _adminService.listOrdersRich();
  }

  void _refresh() => setState(() => _future = _adminService.listOrdersRich());

  void _openDetails(AdminOrderRow o) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OrderDetailsScreen(
        order: Order(
          id: o.id,
          orderNumber: o.orderNumber,
          importerId: o.importerId,
          exporterId: o.exporterId,
          productName: o.productName,
          quantity: 0,
          unit: '',
          unitPrice: 0,
          currency: 'INR',
          totalAmount: o.totalAmount,
          platformFeeAmount: o.platformFeeAmount,
          exporterPayoutAmount: o.exporterPayoutAmount,
          status: o.status,
          autoReleaseDays: 3,
          createdAt: o.createdAt,
        ),
      ),
    ));
  }

  Future<void> _showDocuments(AdminOrderRow o) async {
    final docs = await _tradeService.listDocumentsForOrder(o.id);
    if (!mounted) return;
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
              Text('${o.orderNumber} · Documents', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 12),
              if (docs.isEmpty)
                const Text('No documents generated yet for this order.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5))
              else
                ...docs.map((d) => _DocTile(doc: d)),
            ],
          ),
        ),
      ),
    );
  }

  List<String> get _headers => ['Order #', 'Importer', 'Exporter', 'Logistics', 'Amount', 'Shipment', 'Escrow', 'Order Status', 'Date'];

  List<String> _rowFor(AdminOrderRow o) => [
        o.orderNumber,
        o.importerName,
        o.exporterName,
        o.logisticsName ?? '',
        o.totalAmount.toStringAsFixed(2),
        o.shipmentStatus ?? '',
        o.escrowStatus ?? '',
        o.status,
        o.createdAt.toLocal().toString().split(' ').first,
      ];

  Future<void> _export(List<AdminOrderRow> orders, String format) async {
    setState(() => _exporting = true);
    try {
      if (format == 'pdf') {
        final bytes = await buildAdminTablePdf(title: 'Order Management', headers: _headers, rows: orders.map(_rowFor).toList());
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'orders.pdf');
      } else {
        final csv = buildAdminCsv(_headers, orders.map(_rowFor).toList());
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/orders.csv');
        await file.writeAsString(csv);
        await Share.shareXFiles([XFile(file.path)], text: 'Order Management Export');
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
      appBar: AppBar(title: const Text('Order Management')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminOrderRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final all = snapshot.data ?? [];
            final statuses = all.map((o) => o.status).toSet().toList()..sort();
            final filtered = all.where((o) {
              if (_statusFilter != null && o.status != _statusFilter) return false;
              if (_query.trim().isNotEmpty) {
                final q = _query.trim().toLowerCase();
                if (!o.orderNumber.toLowerCase().contains(q) && !o.importerName.toLowerCase().contains(q) && !o.exporterName.toLowerCase().contains(q) && !o.productName.toLowerCase().contains(q)) return false;
              }
              return true;
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            hintText: 'Search order #, importer, exporter, product',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Theme.of(context).cardTheme.color,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          ),
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
                      ? const Center(child: Text('No orders found.', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final o = filtered[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardTheme.color,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => _openDetails(o),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text(o.orderNumber, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
                                          StatusBadge(status: o.status),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(o.productName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 8),
                                      Text('${o.importerName} → ${o.exporterName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      if (o.logisticsName != null) Text('Logistics: ${o.logisticsName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          _tag('Amount', '₹${o.totalAmount.toStringAsFixed(0)}'),
                                          if (o.shipmentStatus != null) _tag('Shipment', statusLabel(o.shipmentStatus!)),
                                          if (o.escrowStatus != null) _tag('Escrow', statusLabel(o.escrowStatus!)),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _openDetails(o),
                                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8)),
                                              icon: const Icon(Icons.open_in_new, size: 14),
                                              label: const Text('Open Details', style: TextStyle(fontSize: 12)),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _showDocuments(o),
                                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8)),
                                              icon: const Icon(Icons.description_outlined, size: 14),
                                              label: const Text('Documents', style: TextStyle(fontSize: 12)),
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

  Widget _tag(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $value', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }
}

class _DocTile extends StatelessWidget {
  final TradeDocument doc;
  const _DocTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.error),
      title: Text(doc.type.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Text(doc.createdAt.toLocal().toString().split('.').first, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
      trailing: const Icon(Icons.download_outlined, size: 18),
      onTap: () => launchUrl(Uri.parse(doc.fileUrl), mode: LaunchMode.externalApplication),
    );
  }
}
