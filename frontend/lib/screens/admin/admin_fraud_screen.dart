import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';
import '../../widgets/admin_ui_kit.dart';

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
      appBar: AdminGradientAppBar(
        title: 'Fraud & Security',
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Live Signals'), Tab(text: 'Security Flags')]),
      ),
      body: AdminPageBackground(
        child: TabBarView(
          controller: _tabController,
          children: [_buildSignalsTab(), _buildFlagsTab()],
        ),
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
            return const AdminEmptyState(icon: Icons.security_outlined, title: 'No fraud signals detected.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: signals.length,
            itemBuilder: (context, i) {
              final s = signals[i];
              final color = _severityColor(s.severity);
              return AdminReveal(
                index: i,
                child: AdminCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  accent: color,
                  child: Row(
                    children: [
                      AdminIconBadge(icon: Icons.warning_amber_rounded, color: color, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.description, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text(s.email ?? s.userId ?? s.type, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AdminStatusBadge(label: s.severity, color: color),
                    ],
                  ),
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
                  return AdminEmptyState(icon: Icons.shield_outlined, title: _showResolvedOnly ? 'No resolved flags.' : 'No open security flags.');
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: flags.length,
                  itemBuilder: (context, i) {
                    final f = flags[i];
                    final color = _severityColor(f.severity);
                    return AdminReveal(
                      index: i,
                      child: AdminCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        accent: color,
                        child: Row(
                          children: [
                            AdminIconBadge(icon: Icons.shield_outlined, color: color, size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f.description, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 3),
                                  Text('${f.rule} · ${f.createdAt.toLocal().toString().split('.').first}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            f.resolved
                                ? const AdminStatusBadge(label: 'Resolved', color: AppColors.success)
                                : OutlinedButton(onPressed: () => _resolveFlag(f), child: const Text('Resolve')),
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
      ],
    );
  }
}
