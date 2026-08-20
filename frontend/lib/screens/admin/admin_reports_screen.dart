import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_export.dart';
import '../../services/admin_service.dart';
import '../../widgets/admin_ui_kit.dart';

enum _ReportType { revenue, orders, payments, rfqs, users }
enum _Period { daily, weekly, monthly, yearly }

const _reportTypes = [
  (_ReportType.revenue, 'Revenue', Icons.trending_up),
  (_ReportType.orders, 'Orders', Icons.receipt_long_outlined),
  (_ReportType.payments, 'Payments', Icons.account_balance_wallet_outlined),
  (_ReportType.rfqs, 'RFQs', Icons.request_quote_outlined),
  (_ReportType.users, 'Users', Icons.people_outline),
];

const _periods = [
  (_Period.daily, 'Daily'),
  (_Period.weekly, 'Weekly'),
  (_Period.monthly, 'Monthly'),
  (_Period.yearly, 'Yearly'),
];

DateTime _periodStart(_Period p) {
  final now = DateTime.now();
  switch (p) {
    case _Period.daily:
      return DateTime(now.year, now.month, now.day);
    case _Period.weekly:
      return now.subtract(const Duration(days: 7));
    case _Period.monthly:
      return DateTime(now.year, now.month, 1);
    case _Period.yearly:
      return DateTime(now.year, 1, 1);
  }
}

/// Reports — Revenue/Orders/Payments/RFQs/Users, filterable by Daily/Weekly/Monthly/Yearly,
/// exportable as PDF/CSV. Built entirely on data already available from existing admin list
/// endpoints (orders/rich, escrow, rfqs, users/rich) — no new backend required, date
/// filtering happens client-side.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});
  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final _adminService = AdminService();
  _ReportType _type = _ReportType.orders;
  _Period _period = _Period.monthly;
  bool _busy = false;

  Future<(List<String>, List<List<String>>, String)> _buildReport() async {
    final since = _periodStart(_period);
    switch (_type) {
      case _ReportType.orders:
        final rows = (await _adminService.listOrdersRich()).where((o) => o.createdAt.isAfter(since)).toList();
        return (
          ['Order #', 'Importer', 'Exporter', 'Amount', 'Status', 'Date'],
          rows.map((o) => [o.orderNumber, o.importerName, o.exporterName, o.totalAmount.toStringAsFixed(2), o.status, o.createdAt.toLocal().toString().split(' ').first]).toList(),
          'Orders Report',
        );
      case _ReportType.revenue:
        final rows = (await _adminService.listOrdersRich()).where((o) => o.createdAt.isAfter(since) && o.status == 'payment_released').toList();
        return (
          ['Order #', 'Amount', 'Platform Fee', 'Date'],
          rows.map((o) => [o.orderNumber, o.totalAmount.toStringAsFixed(2), o.platformFeeAmount.toStringAsFixed(2), o.createdAt.toLocal().toString().split(' ').first]).toList(),
          'Revenue Report',
        );
      case _ReportType.payments:
        final rows = (await _adminService.listEscrowOrders()).where((e) => e.heldAt == null || e.heldAt!.isAfter(since)).toList();
        return (
          ['Order #', 'Importer', 'Exporter', 'Amount', 'Escrow Status'],
          rows.map((e) => [e.orderNumber, e.importerName, e.exporterName, e.orderAmount.toStringAsFixed(2), e.escrowStatus]).toList(),
          'Payments Report',
        );
      case _ReportType.rfqs:
        final rows = (await _adminService.listAllRFQs()).where((r) => r.createdAt.isAfter(since)).toList();
        return (
          ['RFQ #', 'Importer', 'Product', 'Destination', 'Status', 'Date'],
          rows.map((r) => [r.rfqNumber, r.importerName, r.productName, r.destinationCountry, r.status, r.createdAt.toLocal().toString().split(' ').first]).toList(),
          'RFQ Report',
        );
      case _ReportType.users:
        final rows = (await _adminService.listUsersRich()).where((u) => u.createdAt.isAfter(since)).toList();
        return (
          ['Name', 'Role', 'Email', 'Country', 'Registered'],
          rows.map((u) => [u.fullName, u.role, u.email, u.country ?? '', u.createdAt.toLocal().toString().split(' ').first]).toList(),
          'User Report',
        );
    }
  }

  Future<void> _export(String format) async {
    setState(() => _busy = true);
    try {
      final (headers, rows, title) = await _buildReport();
      if (rows.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data in this period.')));
        return;
      }
      if (format == 'pdf') {
        final bytes = await buildAdminTablePdf(title: '$title — ${_periods.firstWhere((p) => p.$1 == _period).$2}', headers: headers, rows: rows);
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${title.toLowerCase().replaceAll(' ', '-')}.pdf');
      } else {
        final csv = buildAdminCsv(headers, rows);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${title.toLowerCase().replaceAll(' ', '-')}.csv');
        await file.writeAsString(csv);
        await Share.shareXFiles([XFile(file.path)], text: title);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdminGradientAppBar(title: 'Reports'),
      body: AdminPageBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionHeader(icon: Icons.bar_chart_rounded, title: 'Report Type', color: Color(0xFF2563EB)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.4,
                children: _reportTypes
                    .asMap()
                    .entries
                    .map((e) => AdminReveal(index: e.key, child: _typeCard(e.value.$1, e.value.$2, e.value.$3)))
                    .toList(),
              ),
              const SizedBox(height: 20),
              const AdminSectionHeader(icon: Icons.calendar_month_rounded, title: 'Period', color: Color(0xFF7C3AED)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: _periods
                    .map((p) => ChoiceChip(
                          label: Text(p.$2, style: TextStyle(fontSize: 12.5, color: _period == p.$1 ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          selected: _period == p.$1,
                          onSelected: (_) => setState(() => _period = p.$1),
                          selectedColor: AppColors.primary,
                          backgroundColor: Theme.of(context).cardTheme.color,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 28),
              const AdminSectionHeader(icon: Icons.download_rounded, title: 'Download', color: Color(0xFF0EA5E9)),
              const SizedBox(height: 10),
              AdminCard(
                accent: const Color(0xFF0EA5E9),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _export('excel'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        icon: const Icon(Icons.table_chart_outlined, size: 18),
                        label: const Text('Excel (CSV)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : () => _export('pdf'),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('PDF'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeCard(_ReportType type, String label, IconData icon) {
    final selected = _type == type;
    return AdminTapScale(
      onTap: () => setState(() => _type = type),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.1) : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.primary : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 13, color: selected ? AppColors.primary : null)),
          ],
        ),
      ),
    );
  }
}
