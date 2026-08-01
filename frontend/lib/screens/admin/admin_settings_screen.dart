import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';

/// Platform Settings — app branding/contact + SMTP (used by Notification Management's
/// Email channel). Backed by the new GET/PUT /admin/settings endpoints.
///
/// Deliberately does NOT expose Commission % / Escrow Days / Payment Gateway Keys here:
/// those are environment-configured (see backend/internal/config/config.go) and actually
/// used by live fee/escrow calculations — editing a value in this screen that silently
/// didn't affect real orders would be misleading, and there's no payment gateway on this
/// platform to hold keys for (payments are self-declared UPI).
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _adminService = AdminService();
  late Future<PlatformSettings> _future;
  bool _saving = false;

  final _appNameCtrl = TextEditingController();
  final _logoUrlCtrl = TextEditingController();
  final _supportEmailCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();
  final _smtpHostCtrl = TextEditingController();
  final _smtpPortCtrl = TextEditingController();
  final _smtpUsernameCtrl = TextEditingController();
  final _smtpPasswordCtrl = TextEditingController();
  final _smtpFromCtrl = TextEditingController();
  bool _hasSmtpPassword = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PlatformSettings> _load() async {
    final s = await _adminService.getSettings();
    _appNameCtrl.text = s.appName;
    _logoUrlCtrl.text = s.logoUrl ?? '';
    _supportEmailCtrl.text = s.supportEmail ?? '';
    _currencyCtrl.text = s.currency;
    _smtpHostCtrl.text = s.smtpHost ?? '';
    _smtpPortCtrl.text = s.smtpPort?.toString() ?? '';
    _smtpUsernameCtrl.text = s.smtpUsername ?? '';
    _smtpFromCtrl.text = s.smtpFrom ?? '';
    _hasSmtpPassword = s.hasSmtpPassword;
    return s;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _adminService.updateSettings(
        appName: _appNameCtrl.text.trim(),
        logoUrl: _logoUrlCtrl.text.trim().isEmpty ? null : _logoUrlCtrl.text.trim(),
        supportEmail: _supportEmailCtrl.text.trim().isEmpty ? null : _supportEmailCtrl.text.trim(),
        currency: _currencyCtrl.text.trim().isEmpty ? 'INR' : _currencyCtrl.text.trim(),
        smtpHost: _smtpHostCtrl.text.trim().isEmpty ? null : _smtpHostCtrl.text.trim(),
        smtpPort: int.tryParse(_smtpPortCtrl.text.trim()),
        smtpUsername: _smtpUsernameCtrl.text.trim().isEmpty ? null : _smtpUsernameCtrl.text.trim(),
        smtpPassword: _smtpPasswordCtrl.text.trim().isEmpty ? null : _smtpPasswordCtrl.text.trim(),
        smtpFrom: _smtpFromCtrl.text.trim().isEmpty ? null : _smtpFromCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved'), backgroundColor: AppColors.success));
        _smtpPasswordCtrl.clear();
        setState(() => _future = _load());
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _appNameCtrl.dispose();
    _logoUrlCtrl.dispose();
    _supportEmailCtrl.dispose();
    _currencyCtrl.dispose();
    _smtpHostCtrl.dispose();
    _smtpPortCtrl.dispose();
    _smtpUsernameCtrl.dispose();
    _smtpPasswordCtrl.dispose();
    _smtpFromCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: FutureBuilder<PlatformSettings>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionCard(
                  title: 'Application',
                  icon: Icons.apps_outlined,
                  children: [
                    TextField(controller: _appNameCtrl, decoration: const InputDecoration(labelText: 'Application Name')),
                    const SizedBox(height: 12),
                    TextField(controller: _logoUrlCtrl, decoration: const InputDecoration(labelText: 'Logo URL')),
                    const SizedBox(height: 12),
                    TextField(controller: _supportEmailCtrl, decoration: const InputDecoration(labelText: 'Support Email'), keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 12),
                    TextField(controller: _currencyCtrl, decoration: const InputDecoration(labelText: 'Currency Code (e.g. INR)')),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'SMTP (used by Notification Management > Email)',
                  icon: Icons.email_outlined,
                  children: [
                    TextField(controller: _smtpHostCtrl, decoration: const InputDecoration(labelText: 'SMTP Host')),
                    const SizedBox(height: 12),
                    TextField(controller: _smtpPortCtrl, decoration: const InputDecoration(labelText: 'SMTP Port'), keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    TextField(controller: _smtpUsernameCtrl, decoration: const InputDecoration(labelText: 'SMTP Username')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _smtpPasswordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(labelText: _hasSmtpPassword ? 'SMTP Password (configured — leave blank to keep)' : 'SMTP Password'),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: _smtpFromCtrl, decoration: const InputDecoration(labelText: 'From Address')),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.warning.withValues(alpha: 0.2))),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Commission % and Escrow Days are configured on the server (not editable here) since they directly drive live order/escrow calculations. Contact DevOps to change them.',
                          style: TextStyle(color: AppColors.warning, fontSize: 11.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
                  label: const Text('Save Settings'),
                ),
              ],
            ),
          );
        },
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
