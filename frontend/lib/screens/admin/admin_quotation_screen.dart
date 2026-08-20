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

/// Quotation Management — every quotation on the platform, with product/importer/exporter
/// context, status, and CSV/PDF export/download. Backed by the new GET /admin/quotations
/// endpoint. "Download" produces a per-quotation PDF client-side (no backend document type
/// exists for quotations, so this doesn't require any API change).
class AdminQuotationScreen extends StatefulWidget {
  const AdminQuotationScreen({super.key});
  @override
  State<AdminQuotationScreen> createState() => _AdminQuotationScreenState();
}

class _AdminQuotationScreenState extends State<AdminQuotationScreen> {
  final _adminService = AdminService();
  late Future<List<AdminQuotationRow>> _future;
  String _query = '';
  String? _statusFilter;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _adminService.listQuotations();
  }

  void _refresh() => setState(() => _future = _adminService.listQuotations());

  void _showDetails(AdminQuotationRow q) {
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
              Text(q.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 14),
              _row('Quotation #', q.id.substring(0, q.id.length > 8 ? 8 : q.id.length).toUpperCase()),
              _row('Exporter', q.exporterName),
              _row('Importer', q.importerName),
              _row('Unit Price', '₹${q.unitPrice.toStringAsFixed(2)}'),
              _row('Quantity', '${q.quantity}'),
              _row('Amount', '₹${q.totalAmount.toStringAsFixed(2)}'),
              _row('Currency', 'INR'),
              _row('Status', q.status),
              _row('Valid Until', q.validityDate.toLocal().toString().split(' ').first),
              _row('Created', q.createdAt.toLocal().toString().split(' ').first),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _download(q),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Download PDF'),
                ),
              ),
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

  Future<void> _download(AdminQuotationRow q) async {
    setState(() => _busy = true);
    try {
      final bytes = await buildAdminTablePdf(
        title: 'Quotation ${q.id.substring(0, 8).toUpperCase()}',
        headers: ['Field', 'Value'],
        rows: [
          ['Product', q.productName],
          ['Exporter', q.exporterName],
          ['Importer', q.importerName],
          ['Unit Price', '₹${q.unitPrice.toStringAsFixed(2)}'],
          ['Quantity', '${q.quantity}'],
          ['Total Amount', '₹${q.totalAmount.toStringAsFixed(2)}'],
          ['Status', q.status],
          ['Valid Until', q.validityDate.toLocal().toString().split(' ').first],
        ],
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'quotation-${q.id.substring(0, 8)}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> get _headers => ['Quotation #', 'Exporter', 'Importer', 'Amount', 'Currency', 'Status', 'Created'];

  List<String> _rowFor(AdminQuotationRow q) => [
        q.id.substring(0, 8).toUpperCase(),
        q.exporterName,
        q.importerName,
        q.totalAmount.toStringAsFixed(2),
        'INR',
        q.status,
        q.createdAt.toLocal().toString().split(' ').first,
      ];

  Future<void> _export(List<AdminQuotationRow> rows, String format) async {
    setState(() => _busy = true);
    try {
      if (format == 'pdf') {
        final bytes = await buildAdminTablePdf(title: 'Quotation Management', headers: _headers, rows: rows.map(_rowFor).toList());
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'quotations.pdf');
      } else {
        final csv = buildAdminCsv(_headers, rows.map(_rowFor).toList());
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/quotations.csv');
        await file.writeAsString(csv);
        await Share.shareXFiles([XFile(file.path)], text: 'Quotation Management Export');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdminGradientAppBar(title: 'Quotation Management'),
      body: AdminPageBackground(
        child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminQuotationRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final all = snapshot.data ?? [];
            final statuses = all.map((q) => q.status).toSet().toList()..sort();
            final filtered = all.where((q) {
              if (_statusFilter != null && q.status != _statusFilter) return false;
              if (_query.trim().isNotEmpty) {
                final q0 = _query.trim().toLowerCase();
                if (!q.productName.toLowerCase().contains(q0) && !q.exporterName.toLowerCase().contains(q0) && !q.importerName.toLowerCase().contains(q0)) return false;
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
                        child: AdminSearchField(
                          hint: 'Search product, exporter, importer',
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        enabled: !_busy,
                        icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.file_download_outlined),
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
                      ? const AdminEmptyState(
                          icon: Icons.request_quote_outlined,
                          title: 'No quotations found',
                          subtitle: 'Try adjusting your search or filter.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final q = filtered[i];
                            final statusColorValue = statusColor(q.status);
                            return AdminReveal(
                              index: i,
                              child: AdminCard(
                                accent: statusColorValue,
                                onTap: () => _showDetails(q),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        AdminIconBadge(icon: Icons.request_quote_outlined, color: const Color(0xFF2563EB), size: 36),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text(q.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                        AdminStatusBadge(label: statusLabel(q.status), color: statusColorValue),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('${q.exporterName} → ${q.importerName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text('₹${q.totalAmount.toStringAsFixed(2)} · Valid until ${q.validityDate.toLocal().toString().split(' ').first}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _showDetails(q),
                                            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                            icon: const Icon(Icons.visibility_outlined, size: 15),
                                            label: const Text('View'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _busy ? null : () => _download(q),
                                            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                            icon: const Icon(Icons.download_outlined, size: 15),
                                            label: const Text('Download'),
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
