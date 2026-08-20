import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../widgets/admin_ui_kit.dart';

class AdminAuditLogScreen extends StatefulWidget {
  const AdminAuditLogScreen({super.key});
  @override
  State<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends State<AdminAuditLogScreen> {
  final _adminService = AdminService();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _adminService.listAuditLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdminGradientAppBar(title: 'Audit Logs'),
      body: AdminPageBackground(
        child: RefreshIndicator(
          onRefresh: () async => setState(() => _future = _adminService.listAuditLogs()),
          child: FutureBuilder<List<dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final logs = snapshot.data ?? [];
              if (logs.isEmpty) {
                return const AdminEmptyState(
                  icon: Icons.history_toggle_off,
                  title: 'No audit entries yet.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: logs.length,
                itemBuilder: (context, i) {
                  final l = logs[i];
                  final action = (l['action'] ?? '').toString();
                  final actionLower = action.toLowerCase();
                  final Color actionColor = actionLower.contains('delete')
                      ? const Color(0xFFDC2626)
                      : actionLower.contains('update') || actionLower.contains('edit')
                          ? const Color(0xFFCA8A04)
                          : actionLower.contains('create') || actionLower.contains('add')
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF2563EB);
                  return AdminReveal(
                    index: i,
                    child: AdminCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      accent: actionColor,
                      child: Row(
                        children: [
                          AdminIconBadge(icon: Icons.receipt_long, color: actionColor, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AdminStatusBadge(label: action, color: actionColor),
                                const SizedBox(height: 6),
                                Text('${l['entity_type']} · ${l['entity_id'] ?? ''}'),
                              ],
                            ),
                          ),
                          Text(
                            (l['created_at'] ?? '').toString().split('T').first,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
