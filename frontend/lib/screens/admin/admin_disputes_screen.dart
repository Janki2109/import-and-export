import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../widgets/admin_ui_kit.dart';

class AdminDisputesScreen extends StatefulWidget {
  const AdminDisputesScreen({super.key});
  @override
  State<AdminDisputesScreen> createState() => _AdminDisputesScreenState();
}

class _AdminDisputesScreenState extends State<AdminDisputesScreen> {
  final _adminService = AdminService();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _adminService.listPendingDisputes();
  }

  void _refresh() => setState(() => _future = _adminService.listPendingDisputes());

  Future<void> _resolve(String disputeId) async {
    String resolution = 'refund';
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Resolve Dispute'),
          content: RadioGroup<String>(
            groupValue: resolution,
            onChanged: (v) => setDialogState(() => resolution = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RadioListTile<String>(
                  title: Text('Refund Importer'),
                  value: 'refund',
                ),
                const RadioListTile<String>(
                  title: Text('Release to Exporter'),
                  value: 'release',
                ),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Resolution notes')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Resolve')),
          ],
        ),
      ),
    );
    if (confirmed != true || notesCtrl.text.trim().isEmpty) {
      notesCtrl.dispose();
      return;
    }
    final notes = notesCtrl.text.trim();
    notesCtrl.dispose();

    try {
      await _adminService.resolveDispute(disputeId, resolution, notes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dispute resolved'), backgroundColor: AppColors.success));
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdminGradientAppBar(title: 'Resolve Disputes'),
      body: AdminPageBackground(
        child: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: FutureBuilder<List<dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final disputes = snapshot.data ?? [];
              if (disputes.isEmpty) {
                return const AdminEmptyState(icon: Icons.gavel_outlined, title: 'No open disputes.');
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: disputes.length,
                itemBuilder: (context, i) {
                  final d = disputes[i];
                  return AdminReveal(
                    index: i,
                    child: AdminCard(
                      accent: const Color(0xFFDB2777),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const AdminIconBadge(icon: Icons.report_problem_outlined, color: Color(0xFFDB2777), size: 34),
                              const SizedBox(width: 10),
                              Expanded(child: Text(d['reason'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Order: ${d['order_id']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(onPressed: () => _resolve(d['id']), child: const Text('Resolve')),
                          ),
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
