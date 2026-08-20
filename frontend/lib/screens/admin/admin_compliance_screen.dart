import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../models/compliance.dart';
import '../../services/compliance_service.dart';
import '../../widgets/admin_ui_kit.dart';

const _statusFilters = [null, 'uploaded', 'verified', 'rejected', 'pending'];
const _statusLabels = {null: 'All', 'uploaded': 'Pending Review', 'verified': 'Verified', 'rejected': 'Rejected', 'pending': 'Not Uploaded'};

/// Admin Compliance Center — additive admin module. Summary cards, filterable checklist
/// across every order, verify/reject actions, and rule management (how new trade lanes —
/// e.g. Japan -> Brazil — get supported without any code change: insert a row here).
class AdminComplianceScreen extends StatefulWidget {
  const AdminComplianceScreen({super.key});
  @override
  State<AdminComplianceScreen> createState() => _AdminComplianceScreenState();
}

class _AdminComplianceScreenState extends State<AdminComplianceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AdminGradientAppBar(
        title: 'Compliance Center',
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Documents'), Tab(text: 'Rules')]),
      ),
      body: AdminPageBackground(
        child: TabBarView(
          controller: _tabController,
          children: const [_ComplianceDocumentsTab(), _ComplianceRulesTab()],
        ),
      ),
    );
  }
}

class _ComplianceDocumentsTab extends StatefulWidget {
  const _ComplianceDocumentsTab();
  @override
  State<_ComplianceDocumentsTab> createState() => _ComplianceDocumentsTabState();
}

class _ComplianceDocumentsTabState extends State<_ComplianceDocumentsTab> {
  final _service = ComplianceService();
  late Future<List<AdminComplianceRow>> _future;
  late Future<ComplianceSummary> _summaryFuture;
  String? _statusFilter;
  String _query = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _service.adminList();
    _summaryFuture = _service.adminSummary();
  }

  void _refresh() => setState(() {
        _future = _service.adminList(status: _statusFilter);
        _summaryFuture = _service.adminSummary();
      });

  Future<void> _verify(AdminComplianceRow row) async {
    setState(() => _busy = true);
    try {
      await _service.verifyDocument(row.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document verified'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(AdminComplianceRow row) async {
    final remarksCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reject Document'),
        content: TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Reason for rejection')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _service.rejectDocument(row.id, remarksCtrl.text.trim().isEmpty ? 'Rejected by admin' : remarksCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document rejected'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'verified':
        return AppColors.success;
      case 'uploaded':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<ComplianceSummary>(
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
                  _summaryCard('Pending Verification', '${s?.pendingVerification ?? '—'}', Icons.hourglass_top_outlined, AppColors.warning),
                  _summaryCard('Verified Documents', '${s?.verified ?? '—'}', Icons.verified_outlined, AppColors.success),
                  _summaryCard('Rejected Documents', '${s?.rejected ?? '—'}', Icons.cancel_outlined, AppColors.error),
                  _summaryCard('Blocked Shipments', '${s?.blockedShipments ?? '—'}', Icons.block, Colors.purple),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          AdminSearchField(
            hint: 'Search by order #, document, importer, exporter',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _statusFilters
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(_statusLabels[s]!, style: TextStyle(fontSize: 12, color: _statusFilter == s ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          selected: _statusFilter == s,
                          onSelected: (_) {
                            setState(() => _statusFilter = s);
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
          FutureBuilder<List<AdminComplianceRow>>(
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
                    r.documentName.toLowerCase().contains(q) ||
                    r.importerName.toLowerCase().contains(q) ||
                    r.exporterName.toLowerCase().contains(q)).toList();
              }
              if (rows.isEmpty) {
                return const AdminEmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'No compliance documents found.',
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
                    accent: color,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(row.documentName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            AdminStatusBadge(label: statusLabel(row.status), color: color),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${row.orderNumber} · ${row.responsibleRole}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                        const SizedBox(height: 4),
                        Text('${row.importerName} ← ${row.exporterName}${row.logisticsName != null ? ' · ${row.logisticsName}' : ''}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (row.originCountry != null || row.destinationCountry != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('${row.originCountry ?? '—'} → ${row.destinationCountry ?? '—'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (row.uploadedFile != null)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => launchUrl(Uri.parse(row.uploadedFile!), mode: LaunchMode.externalApplication),
                                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8)),
                                  icon: const Icon(Icons.visibility_outlined, size: 14),
                                  label: const Text('Preview', style: TextStyle(fontSize: 12)),
                                ),
                              ),
                            if (row.status == 'uploaded') ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy ? null : () => _reject(row),
                                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8), foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                                  icon: const Icon(Icons.close, size: 14),
                                  label: const Text('Reject', style: TextStyle(fontSize: 12)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _busy ? null : () => _verify(row),
                                  style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 8)),
                                  icon: const Icon(Icons.check, size: 14),
                                  label: const Text('Verify', style: TextStyle(fontSize: 12)),
                                ),
                              ),
                            ],
                          ],
                        ),
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

/// Rule management — this is how new trade lanes (Japan -> Brazil, Germany -> Australia,
/// India -> USA, China -> UAE, ...) get supported: insert a row here, no code change.
class _ComplianceRulesTab extends StatefulWidget {
  const _ComplianceRulesTab();
  @override
  State<_ComplianceRulesTab> createState() => _ComplianceRulesTabState();
}

class _ComplianceRulesTabState extends State<_ComplianceRulesTab> {
  final _service = ComplianceService();
  late Future<List<ComplianceRule>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.listRules();
  }

  void _refresh() => setState(() => _future = _service.listRules());

  Future<void> _delete(ComplianceRule rule) async {
    try {
      await _service.deleteRule(rule.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rule deleted'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _showAddRule() async {
    final originCtrl = TextEditingController();
    final destCtrl = TextEditingController();
    final hsCtrl = TextEditingController();
    final docNameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String mode = 'any';
    String role = 'exporter';
    bool mandatory = true;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('New Compliance Rule', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 4),
                const Text('Leave a field blank to make it a wildcard (applies to all).', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                const SizedBox(height: 16),
                TextField(controller: originCtrl, decoration: const InputDecoration(labelText: 'Origin Country (optional)')),
                const SizedBox(height: 10),
                TextField(controller: destCtrl, decoration: const InputDecoration(labelText: 'Destination Country (optional)')),
                const SizedBox(height: 10),
                TextField(controller: hsCtrl, decoration: const InputDecoration(labelText: 'HS Code (optional)')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Shipping Mode'),
                  items: const [
                    DropdownMenuItem(value: 'any', child: Text('Any')),
                    DropdownMenuItem(value: 'air', child: Text('Air')),
                    DropdownMenuItem(value: 'sea', child: Text('Sea')),
                    DropdownMenuItem(value: 'road', child: Text('Road')),
                    DropdownMenuItem(value: 'rail', child: Text('Rail')),
                  ],
                  onChanged: (v) => setSheetState(() => mode = v ?? 'any'),
                ),
                const SizedBox(height: 10),
                TextField(controller: docNameCtrl, decoration: const InputDecoration(labelText: 'Document Name')),
                const SizedBox(height: 10),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description (optional)'), maxLines: 2),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Responsible Role'),
                  items: const [
                    DropdownMenuItem(value: 'exporter', child: Text('Exporter')),
                    DropdownMenuItem(value: 'importer', child: Text('Importer')),
                    DropdownMenuItem(value: 'logistics', child: Text('Logistics')),
                  ],
                  onChanged: (v) => setSheetState(() => role = v ?? 'exporter'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mandatory'),
                  value: mandatory,
                  onChanged: (v) => setSheetState(() => mandatory = v),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    if (docNameCtrl.text.trim().isEmpty) return;
                    try {
                      await _service.createRule(
                        originCountry: originCtrl.text.trim().isEmpty ? null : originCtrl.text.trim(),
                        destinationCountry: destCtrl.text.trim().isEmpty ? null : destCtrl.text.trim(),
                        hsCode: hsCtrl.text.trim().isEmpty ? null : hsCtrl.text.trim(),
                        shippingMode: mode == 'any' ? null : mode,
                        documentName: docNameCtrl.text.trim(),
                        responsibleRole: role,
                        mandatory: mandatory,
                        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
                    }
                  },
                  child: const Text('Create Rule'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
    if (created == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRule,
        icon: const Icon(Icons.add),
        label: const Text('New Rule'),
      ),
      body: AdminPageBackground(
        child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<ComplianceRule>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final rules = snapshot.data ?? [];
            if (rules.isEmpty) {
              return const AdminEmptyState(
                icon: Icons.rule_folder_outlined,
                title: 'No compliance rules configured yet.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: rules.length,
              itemBuilder: (context, i) {
                final rule = rules[i];
                return AdminReveal(
                  index: i,
                  child: AdminCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  accent: const Color(0xFFCA8A04),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rule.documentName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text(
                              '${rule.originCountry ?? 'Any'} → ${rule.destinationCountry ?? 'Any'} · ${rule.shippingMode ?? 'Any mode'} · ${rule.hsCode ?? 'Any HS Code'}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            ),
                            const SizedBox(height: 3),
                            Text('${rule.responsibleRole} · ${rule.mandatory ? 'Mandatory' : 'Optional'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.error), onPressed: () => _delete(rule)),
                    ],
                  ),
                  ),
                );
              },
            );
          },
        ),
        ),
      ),
    );
  }
}
