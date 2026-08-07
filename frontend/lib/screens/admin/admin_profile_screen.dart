import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../widgets/theme_toggle_button.dart';
import '../onboarding/language_screen.dart';
import '../profile/change_password_screen.dart';
import '../profile/security_dashboard_screen.dart';

/// Admin's Profile — mirrors the structure of the importer/exporter ProfileScreen
/// (frontend/lib/screens/profile/profile_screen.dart): gradient header card, info
/// sections, then a settings list. Backed by the same authProvider.currentUser the rest
/// of the admin shell already reads (no new backend calls). "Permissions" and "2FA
/// Status" are shown honestly — this backend has a single Super Admin role with full
/// access and no 2FA flow, so they're presented as static facts rather than fabricated
/// toggles wired to endpoints that don't exist.
class AdminProfileScreen extends ConsumerWidget {
  const AdminProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          _HeaderCard(name: user?.fullName ?? 'Admin', email: user?.email ?? ''),
          const SizedBox(height: 24),
          _SectionCard(
            icon: Icons.person_outline,
            title: 'Account Information',
            children: [
              _infoRow('Full Name', user?.fullName ?? '—'),
              _infoRow('Email', user?.email ?? '—'),
              _infoRow('Phone', user?.phone ?? '—'),
              _infoRow('Role', 'Super Admin'),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.shield_outlined,
            title: 'Access & Security',
            children: [
              _infoRow('Permissions', 'Full platform access'),
              _infoRow('Last Login', 'This session'),
              _infoRow('2FA Status', 'Not Enabled'),
            ],
          ),
          const SizedBox(height: 24),
          Text('Settings', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _SettingsCard(),
        ],
      ),
    );
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
        ],
      ),
    );
  }
}

/// Gradient header — same visual language as the Exporter/Importer welcome card and the
/// shared ProfileScreen's header (avatar, name, verified badge).
class _HeaderCard extends StatelessWidget {
  final String name;
  final String email;
  const _HeaderCard({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? [AppColorsDark.primary, AppColorsDark.secondary] : [const Color(0xFF0B3D91), const Color(0xFF1857C4)];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 42,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'A', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 14),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(email, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xFF6FE3A5).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, size: 14, color: Color(0xFF6FE3A5)),
                SizedBox(width: 6),
                Text('Super Admin — Verified', style: TextStyle(color: Color(0xFF6FE3A5), fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 18, color: AppColors.primary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))]),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        children: [
          _tile(context, Icons.shield_outlined, 'Security', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SecurityDashboardScreen()))),
          const Divider(height: 1),
          _tile(context, Icons.lock_outline, 'Change Password', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()))),
          const Divider(height: 1),
          _tile(context, Icons.language_outlined, 'Language', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LanguageScreen(isSettingsChange: true)))),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.dark_mode_outlined, color: AppColors.primary),
            title: Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: ThemeToggleButton(),
          ),
          const Divider(height: 1),
          _tile(context, Icons.campaign_outlined, 'Notification Settings', () => _showStaticInfo(context, 'Notification Settings',
              'Platform-wide notifications are managed from the admin "Notifications" section (compose & broadcast). Personal in-app alerts use the same bell icon as every other role.')),
          const Divider(height: 1),
          _tile(context, Icons.privacy_tip_outlined, 'Privacy', () => _showStaticInfo(context, 'Privacy Policy',
              'Admin accounts have access to the data required for platform operation, KYC verification, and dispute resolution only. All admin actions are recorded in the Audit Log.')),
          const Divider(height: 1),
          _tile(context, Icons.info_outline, 'About App', () => _showStaticInfo(context, 'About ${AppConstants.appName}',
              '${AppConstants.appName}\nVersion 1.0.0\n\nAdmin Panel — manage users, KYC, orders, escrow, disputes, and platform settings.')),
          const Divider(height: 1),
          _tile(context, Icons.logout, 'Logout', () => _confirmLogout(context, ref), color: AppColors.error),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.primary),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _showStaticInfo(BuildContext context, String title, String body) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 12),
              Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider).logout();
    }
  }
}
