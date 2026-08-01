import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';

const _targets = [
  (null, 'All Users'),
  ('importer', 'Importers'),
  ('exporter', 'Exporters'),
  ('logistics', 'Logistics'),
];

/// Notification Management — compose and send a notification to a targeted audience.
/// Two real channels exist in this backend: "In-App & Push" (the same mechanism every
/// other notification in the app uses — bell icon + FCM push if a device is registered)
/// and "Email" (via SMTP, configured in Settings). Backed by the new
/// POST /admin/notifications/broadcast endpoint.
class AdminNotificationScreen extends StatefulWidget {
  const AdminNotificationScreen({super.key});
  @override
  State<AdminNotificationScreen> createState() => _AdminNotificationScreenState();
}

class _AdminNotificationScreenState extends State<AdminNotificationScreen> {
  final _adminService = AdminService();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String? _target;
  bool _sendInApp = true;
  bool _sendEmail = false;
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title and message are required'), backgroundColor: AppColors.error));
      return;
    }
    if (!_sendInApp && !_sendEmail) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one channel'), backgroundColor: AppColors.error));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Send Notification'),
        content: Text('Send "${_titleCtrl.text.trim()}" to ${_targets.firstWhere((t) => t.$1 == _target).$2}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _sending = true);
    try {
      final result = await _adminService.broadcastNotification(
        targetRole: _target,
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        inApp: _sendInApp,
        email: _sendEmail,
      );
      if (mounted) {
        final parts = <String>[];
        if (_sendInApp) parts.add('${result['in_app_sent']} in-app/push');
        if (_sendEmail) parts.add('${result['email_sent']} email');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sent to ${parts.join(' + ')}'), backgroundColor: AppColors.success));
        _titleCtrl.clear();
        _bodyCtrl.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Management')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionCard(
              title: 'Target Audience',
              icon: Icons.group_outlined,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _targets
                      .map((t) => ChoiceChip(
                            label: Text(t.$2, style: TextStyle(fontSize: 12.5, color: _target == t.$1 ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600)),
                            selected: _target == t.$1,
                            onSelected: (_) => setState(() => _target = t.$1),
                            selectedColor: AppColors.primary,
                            backgroundColor: Colors.grey.shade100,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
                          ))
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'Message',
              icon: Icons.edit_note_outlined,
              children: [
                TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title'), maxLength: 100),
                const SizedBox(height: 8),
                TextField(controller: _bodyCtrl, decoration: const InputDecoration(labelText: 'Message'), maxLines: 4, maxLength: 500),
              ],
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'Channels',
              icon: Icons.send_outlined,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _sendInApp,
                  onChanged: (v) => setState(() => _sendInApp = v ?? false),
                  title: const Text('In-App & Push Notification', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  subtitle: const Text('Shows in the notification bell; also pushed via FCM to registered devices.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _sendEmail,
                  onChanged: (v) => setState(() => _sendEmail = v ?? false),
                  title: const Text('Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  subtitle: const Text('Requires SMTP to be configured under Settings.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_outlined),
              label: const Text('Send Notification'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
          ]),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
