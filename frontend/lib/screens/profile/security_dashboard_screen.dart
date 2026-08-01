import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/security.dart';
import '../../services/security_service.dart';

const _gold = Color(0xFFD4AF37);

/// Security Dashboard (Part 12) — security score, verification status, active devices,
/// login history, recent document access. Read-only view over the new /security/* backend
/// endpoints; device trust/logout are the only mutating actions here.
class SecurityDashboardScreen extends StatefulWidget {
  const SecurityDashboardScreen({super.key});
  @override
  State<SecurityDashboardScreen> createState() => _SecurityDashboardScreenState();
}

class _SecurityDashboardScreenState extends State<SecurityDashboardScreen> {
  final _service = SecurityService();
  late Future<SecurityOverview> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _service.getOverview();
  }

  void _refresh() => setState(() => _future = _service.getOverview());

  Future<void> _run(Future<void> Function() action, {String? successMessage}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        if (successMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage), backgroundColor: AppColors.success));
        }
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmLogoutAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout From All Devices'),
        content: const Text('This will sign you out everywhere, including this device. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Logout All')),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => _service.logoutAllDevices(), successMessage: 'Logged out from all devices');
    }
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<SecurityOverview>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final o = snapshot.data!;
            final color = _scoreColor(o.securityScore);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _scoreCard(o, color),
                const SizedBox(height: 16),
                _statusGrid(o),
                const SizedBox(height: 20),
                Text('Active Devices (${o.devices.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (o.devices.isEmpty)
                  const _EmptyRow(text: 'No devices registered yet.')
                else
                  ...o.devices.map((d) => _deviceCard(d)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmLogoutAll,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Logout From All Devices'),
                ),
                const SizedBox(height: 20),
                Text('Login History', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (o.loginHistory.isEmpty)
                  const _EmptyRow(text: 'No login history yet.')
                else
                  ...o.loginHistory.take(10).map((h) => _historyRow(h)),
                const SizedBox(height: 20),
                Text('Recent Document Access', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (o.recentDocumentAccess.isEmpty)
                  const _EmptyRow(text: 'No document access recorded yet.')
                else
                  ...o.recentDocumentAccess.take(10).map((d) => _docAccessRow(d)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _scoreCard(SecurityOverview o, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(value: o.securityScore / 100, strokeWidth: 7, backgroundColor: Colors.white.withValues(alpha: 0.2), valueColor: const AlwaysStoppedAnimation(_gold)),
                Text('${o.securityScore}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Security Score', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  o.securityScore >= 80 ? 'Your account is well protected.' : 'Verify your email/phone to strengthen your account.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (o.lastLoginAt != null) ...[
                  const SizedBox(height: 8),
                  Text('Last login: ${o.lastLoginAt!.toLocal().toString().split('.').first}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusGrid(SecurityOverview o) {
    final items = [
      ('Password', 'Set', Icons.lock_outline, AppColors.success),
      ('Multi-Factor Auth', o.mfaEnabled ? 'Enabled' : 'Not Set Up', Icons.verified_user_outlined, o.mfaEnabled ? AppColors.success : AppColors.textSecondary),
      ('Email', o.emailVerified ? 'Verified' : 'Not Verified', Icons.email_outlined, o.emailVerified ? AppColors.success : AppColors.warning),
      ('Phone', o.phoneVerified ? 'Verified' : 'Not Verified', Icons.phone_outlined, o.phoneVerified ? AppColors.success : AppColors.warning),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: items
          .map((it) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]),
                child: Row(
                  children: [
                    Icon(it.$3, size: 18, color: it.$4),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(it.$1, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(it.$2, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: it.$4), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _deviceCard(SecurityDevice d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: (d.trusted ? AppColors.success : AppColors.primary).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(d.platform == 'ios' ? Icons.phone_iphone : Icons.smartphone, size: 18, color: d.trusted ? AppColors.success : AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(child: Text(d.deviceName ?? d.deviceId, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (d.trusted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: const Text('TRUSTED', style: TextStyle(color: AppColors.success, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                ]),
                const SizedBox(height: 2),
                Text('${d.lastCountry ?? 'Unknown location'} · Last seen ${d.lastSeen.toLocal().toString().split(' ').first}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'trust') _run(() => _service.trustDevice(d.id), successMessage: 'Device marked as trusted');
              if (v == 'logout') _run(() => _service.logoutDevice(d.id), successMessage: 'Device logged out');
            },
            itemBuilder: (ctx) => [
              if (!d.trusted) const PopupMenuItem(value: 'trust', child: Text('Mark as Trusted')),
              const PopupMenuItem(value: 'logout', child: Text('Logout This Device')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyRow(LoginHistoryEntry h) {
    final color = h.success ? AppColors.success : AppColors.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(h.success ? Icons.check_circle_outline : Icons.error_outline, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${h.success ? 'Successful login' : 'Failed login'} · ${h.country ?? 'Unknown'} · ${h.createdAt.toLocal().toString().split('.').first}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _docAccessRow(DocumentAccessEntry d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(d.action == 'download' ? Icons.download_outlined : Icons.visibility_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${d.action == 'download' ? 'Downloaded' : 'Viewed'} document · ${d.createdAt.toLocal().toString().split('.').first}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String text;
  const _EmptyRow({required this.text});
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5));
}
