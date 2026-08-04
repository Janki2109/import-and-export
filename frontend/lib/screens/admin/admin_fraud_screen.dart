import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';

/// Journey 12 — "Fraud Signals" (live, recomputed every load) and "Security Flags" (persisted,
/// reviewable/resolvable over time) are related but distinct: signals are ephemeral heuristics,
/// flags are the durable record of what Sweep() actually found and acted on. Both live here as
/// tabs of one screen rather than two separate nav entries.
class AdminFraudScreen extends StatefulWidget {
  const AdminFraudScreen({super.key});
  @override
  State<AdminFraudScreen> createState() => _AdminFraudScreenState();
}

class _AdminFraudScreenState extends State<AdminFraudScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _adminService = AdminService();
  late Future<List<FraudSignal>> _signalsFuture;
  late Future<List<SecurityFlag>> _flagsFuture;
  bool _showResolvedOnly = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _signalsFuture = _adminService.getFraudSignals();
    _flagsFuture = _adminService.listSecurityFlags(resolved: false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshFlags() => setState(() => _flagsFuture = _adminService.listSecurityFlags(resolved: _showResolvedOnly ? true : false));

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

  Future<void> _resolveFlag(SecurityFlag flag) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve Security Flag'),
        content: Text(flag.description),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'dismiss'), child: const Text('Dismiss')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'warn'), child: const Text('Warn User')),
        ],
      ),
    );
    if (action == null) return;
    try {
      await _adminService.resolveSecurityFlag(flag.id, action: action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flag resolved'), backgroundColor: AppColors.success));
        _refreshFlags();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fraud & Security'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Live Signals'), Tab(text: 'Security Flags')]),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSignalsTab(), _buildFlagsTab()],
      ),
    );
  }

  Widget _buildSignalsTab() {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _signalsFuture = _adminService.getFraudSignals()),
      child: FutureBuilder<List<FraudSignal>>(
        future: _signalsFuture,
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
    );
  }

  Widget _buildFlagsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Show resolved'),
              Switch(
                value: _showResolvedOnly,
                onChanged: (v) {
                  setState(() => _showResolvedOnly = v);
                  _refreshFlags();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refreshFlags(),
            child: FutureBuilder<List<SecurityFlag>>(
              future: _flagsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final flags = snapshot.data ?? [];
                if (flags.isEmpty) {
                  return Center(child: Text(_showResolvedOnly ? 'No resolved flags.' : 'No open security flags.', style: const TextStyle(color: AppColors.textSecondary)));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: flags.length,
                  itemBuilder: (context, i) {
                    final f = flags[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(Icons.shield_outlined, color: _severityColor(f.severity)),
                        title: Text(f.description),
                        subtitle: Text('${f.rule} · ${f.createdAt.toLocal().toString().split('.').first}'),
                        trailing: f.resolved
                            ? const Chip(label: Text('Resolved'), backgroundColor: AppColors.success)
                            : OutlinedButton(onPressed: () => _resolveFlag(f), child: const Text('Resolve')),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
