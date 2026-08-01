import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';

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
      appBar: AppBar(title: const Text('Audit Logs')),
      body: RefreshIndicator(
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
              return const Center(child: Text('No audit entries yet.', style: TextStyle(color: AppColors.textSecondary)));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              itemBuilder: (context, i) {
                final l = logs[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text(l['action'] ?? ''),
                    subtitle: Text('${l['entity_type']} · ${l['entity_id'] ?? ''}'),
                    trailing: Text(
                      (l['created_at'] ?? '').toString().split('T').first,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
