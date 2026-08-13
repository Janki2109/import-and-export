import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../features/onboarding/screens/onboarding_flow_screen.dart';
import '../../models/company.dart';
import '../../models/user.dart';
import '../../providers/providers.dart';
import '../../services/company_service.dart';
import '../../services/kyc_service.dart';
import '../../services/chat_service.dart';
import '../../services/profile_service.dart';
import '../chat/chat_screen.dart';
import '../onboarding/language_screen.dart';
import '../shared/kyc_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
import 'security_dashboard_screen.dart';

/// Importer's Profile — read-only view of the account, backed by the same GET /users/me,
/// GET /company/me, and GET /kyc/me endpoints used elsewhere (KYC screen, onboarding).
/// Editing (name/email/phone/photo/company/business details) opens EditProfileScreen;
/// GST/IEC are shown here but edited via the existing KYCScreen, since changing them
/// re-triggers the real (unchanged) KYC re-verification workflow.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _profileService = ProfileService();
  final _companyService = CompanyService();
  final _kycService = KYCService();

  late Future<_ProfileBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ProfileBundle> _load() async {
    final results = await Future.wait([
      _profileService.getProfile(),
      _companyService.getMine(),
      _kycService.getMyStatus(),
    ]);
    return _ProfileBundle(
      user: results[0] as AppUser,
      company: results[1] as Company?,
      kyc: results[2] as Map<String, dynamic>,
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<_ProfileBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load profile: ${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              ),
            );
          }
          final bundle = snapshot.data!;
          final kycStatus = bundle.kyc['status'] as String? ?? 'pending';
          final isVerified = kycStatus == 'verified';

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                _HeaderCard(
                  user: bundle.user,
                  isVerified: isVerified,
                  onEdit: () async {
                    final updated = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => EditProfileScreen(user: bundle.user, company: bundle.company)),
                    );
                    if (updated == true) _refresh();
                  },
                ),
                const SizedBox(height: 24),
                _SectionCard(
                  icon: Icons.person_outline,
                  title: 'Personal Information',
                  children: [
                    _infoRow('Full Name', bundle.user.fullName),
                    _infoRow('Email', bundle.user.email),
                    _infoRow('Mobile Number', bundle.user.phone),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  icon: Icons.apartment_outlined,
                  title: 'Company Information',
                  children: [
                    _infoRow('Company Name', bundle.company?.companyName ?? bundle.user.companyName ?? 'Not specified'),
                    _infoRow('GST Number', bundle.kyc['gst_number'] ?? 'Not specified'),
                    _infoRow('IEC Number', bundle.kyc['iec_code'] ?? 'Not specified'),
                    _infoRow('Business Address', bundle.company?.address ?? 'Not specified'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KYCScreen())).then((_) => _refresh()),
                        icon: const Icon(Icons.verified_user_outlined, size: 16),
                        label: const Text('Edit GST / IEC via KYC Verification'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Business Details',
                  children: [
                    _infoRow('Products Imported', bundle.company?.productsImported ?? 'Not specified'),
                    _infoRow('Preferred Shipping Mode', bundle.company?.preferredShippingMode ?? 'Not specified'),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Settings', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _SettingsCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
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

class _ProfileBundle {
  final AppUser user;
  final Company? company;
  final Map<String, dynamic> kyc;
  _ProfileBundle({required this.user, required this.company, required this.kyc});
}

/// Gradient header with photo, name, company, contact info, verification badge, and an
/// Edit Profile button.
class _HeaderCard extends StatelessWidget {
  final AppUser user;
  final bool isVerified;
  final VoidCallback onEdit;
  const _HeaderCard({required this.user, required this.isVerified, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 42,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            backgroundImage: user.avatarUrl != null ? CachedNetworkImageProvider(user.avatarUrl!) : null,
            child: user.avatarUrl == null
                ? Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800))
                : null,
          ),
          const SizedBox(height: 14),
          Text(user.fullName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          if (user.companyName != null) ...[
            const SizedBox(height: 2),
            Text(user.companyName!, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _chip(Icons.email_outlined, user.email),
              _chip(Icons.phone_outlined, user.phone),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: (isVerified ? AppColors.success : AppColors.warning).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isVerified ? Icons.verified : Icons.hourglass_top_outlined, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(isVerified ? 'Importer — Verified' : 'Importer — Pending', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Profile'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11.5)),
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
    final role = ref.read(authProvider).currentUser?.role;
    return Card(
      child: Column(
        children: [
          _tile(context, Icons.shield_outlined, 'Security', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SecurityDashboardScreen()))),
          const Divider(height: 1),
          _tile(context, Icons.lock_outline, 'Change Password', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()))),
          const Divider(height: 1),
          _tile(context, Icons.language_outlined, 'Change Language', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LanguageScreen(isSettingsChange: true)))),
          const Divider(height: 1),
          // Additive — role-specific app guide replay. Admin has no onboarding flow, so this
          // entry is hidden for admin rather than opening an empty screen.
          if (role != null && role != UserRole.admin) ...[
            _tile(context, Icons.explore_outlined, 'View App Guide',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingFlowScreen(isReplay: true)))),
            const Divider(height: 1),
          ],
          _tile(context, Icons.help_outline, 'Help & Support', () => _openSupportChat(context)),
          const Divider(height: 1),
          _tile(context, Icons.privacy_tip_outlined, 'Privacy Policy', () => _showStaticInfo(context, 'Privacy Policy',
              'We collect only the information required to operate your account, KYC verification, and trade transactions. Your data is never sold to third parties. Documents you upload (KYC, PODs) are stored securely and only accessible to you and platform admins for verification purposes.')),
          const Divider(height: 1),
          _tile(context, Icons.info_outline, 'About App', () => _showStaticInfo(context, 'About ${AppConstants.appName}',
              '${AppConstants.appName}\nVersion 1.0.0\n\nA complete import-export trade platform connecting importers, exporters, and logistics partners — RFQs, escrow-protected orders, shipment tracking, and trade document generation, all in one place.')),
          const Divider(height: 1),
          _tile(context, Icons.logout, 'Logout', () => _confirmLogout(context, ref), color: AppColors.error),
        ],
      ),
    );
  }

  /// Help & Support — jumps straight into the existing support conversation with admin,
  /// same call sequence as StartChatScreen's "Chat with Support" (getSupportContact ->
  /// startConversation -> ChatScreen). No more info popup.
  Future<void> _openSupportChat(BuildContext context) async {
    final chatService = ChatService();
    try {
      final admin = await chatService.getSupportContact();
      final conversationId = await chatService.startConversation(admin['user_id']!);
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conversationId, otherUserName: admin['full_name'] ?? 'Support')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
      }
    }
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
      // Same AuthProvider.logout() the rest of the app uses — clears the session, and
      // GoRouter's existing redirect sends the user to /login and (being a redirect, not a
      // push) removes the dashboard from the navigation stack so back can't return to it.
      await ref.read(authProvider).logout();
    }
  }
}
