import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';

class AdminFraudScreen extends StatefulWidget {
  const AdminFraudScreen({super.key});
  @override
  State<AdminFraudScreen> createState() => _AdminFraudScreenState();
}

class _AdminFraudScreenState extends State<AdminFraudScreen> {
  final _adminService = AdminService();
  late Future<List<FraudSignal>> _future;

  @override
  void initState() {
    super.initState();
    _future = _adminService.getFraudSignals();
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'high':
        return AppColors.error;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fraud Signals')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = _adminService.getFraudSignals()),
        child: FutureBuilder<List<FraudSignal>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final signals = snapshot.data ?? [];
            if (signals.isEmpty) {
              return const Center(child: Text('No fraud signals detected.', style: TextStyle(color: AppColors.textSecondary)));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: signals.length,
              itemBuilder: (context, i) {
                final s = signals[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(Icons.warning_amber_rounded, color: _severityColor(s.severity)),
                    title: Text(s.description),
                    subtitle: Text(s.email ?? s.userId ?? s.type),
                    trailing: Chip(label: Text(s.severity), backgroundColor: _severityColor(s.severity).withValues(alpha: 0.12)),
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
