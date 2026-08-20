import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../widgets/admin_ui_kit.dart';

/// Admin queue for reviewing KYC submissions — four tabs (Pending / Approved / Rejected /
/// Need Re-upload), each showing the applicant's identity (avatar, name, role, country,
/// company) plus every declared number and uploaded document, so the admin can review a
/// full-screen copy of each document before deciding.
class AdminKYCReviewScreen extends StatefulWidget {
  const AdminKYCReviewScreen({super.key});
  @override
  State<AdminKYCReviewScreen> createState() => _AdminKYCReviewScreenState();
}

class _KYCTab {
  final String label;
  final String status; // matches KYCService.ListByStatus's `status` query param
  final IconData icon;
  const _KYCTab(this.label, this.status, this.icon);
}

const _kTabs = [
  _KYCTab('Pending', 'pending', Icons.hourglass_top_outlined),
  _KYCTab('Approved', 'verified', Icons.verified_outlined),
  _KYCTab('Rejected', 'rejected', Icons.cancel_outlined),
  _KYCTab('Need Re-upload', 'needs_reupload', Icons.upload_file_outlined),
];

class _AdminKYCReviewScreenState extends State<AdminKYCReviewScreen> with SingleTickerProviderStateMixin {
  final _adminService = AdminService();
  late final TabController _tabController;
  final Map<int, Future<List<dynamic>>> _futures = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kTabs.length, vsync: this);
    _load(0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _load(int index) {
    _futures[index] = _adminService.listKYCByStatus(_kTabs[index].status);
  }

  void _refresh(int index) => setState(() => _load(index));

  Future<void> _approve(String userId, int tabIndex) async {
    try {
      await _adminService.approveKYC(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KYC approved — the user has been notified.'), backgroundColor: AppColors.success),
        );
      }
      _refresh(tabIndex);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<String?> _promptReason(String title, String actionLabel, Color actionColor) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason'), autofocus: true, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: actionColor),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true || reason.isEmpty) return null;
    return reason;
  }

  Future<void> _reject(String userId, int tabIndex) async {
    final reason = await _promptReason('Reject KYC', 'Reject', AppColors.error);
    if (reason == null) return;
    try {
      await _adminService.rejectKYC(userId, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KYC rejected — the user has been notified.'), backgroundColor: AppColors.warning),
        );
      }
      _refresh(tabIndex);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _requestReupload(String userId, int tabIndex) async {
    final reason = await _promptReason('Request Re-upload', 'Request', AppColors.primary);
    if (reason == null) return;
    try {
      await _adminService.requestKYCReupload(userId, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Re-upload requested — the user has been notified.'), backgroundColor: AppColors.primary),
        );
      }
      _refresh(tabIndex);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  void _openDetails(Map<String, dynamic> k, int tabIndex) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _KYCDetailScreen(
        kyc: k,
        tabIndex: tabIndex,
        onApprove: () => _approve(k['user_id'], tabIndex),
        onReject: () => _reject(k['user_id'], tabIndex),
        onRequestReupload: () => _requestReupload(k['user_id'], tabIndex),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AdminGradientAppBar(
        title: 'KYC Review',
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          onTap: (i) => setState(() {}), // rebuild so the FutureBuilder below picks up the tab
          tabs: _kTabs.map((t) => Tab(icon: Icon(t.icon, size: 18), text: t.label)).toList(),
        ),
      ),
      body: AdminPageBackground(
        child: TabBarView(
          controller: _tabController,
          children: List.generate(_kTabs.length, (i) => _KYCList(
                future: _futures[i] ??= _adminService.listKYCByStatus(_kTabs[i].status),
                tabIndex: i,
                onRefresh: () async => _refresh(i),
                onOpenDetails: (k) => _openDetails(k, i),
                onApprove: (userId) => _approve(userId, i),
                onReject: (userId) => _reject(userId, i),
                onRequestReupload: (userId) => _requestReupload(userId, i),
              )),
        ),
      ),
    );
  }
}

class _KYCList extends StatelessWidget {
  final Future<List<dynamic>> future;
  final int tabIndex;
  final Future<void> Function() onRefresh;
  final void Function(Map<String, dynamic>) onOpenDetails;
  final void Function(String userId) onApprove;
  final void Function(String userId) onReject;
  final void Function(String userId) onRequestReupload;

  const _KYCList({
    required this.future,
    required this.tabIndex,
    required this.onRefresh,
    required this.onOpenDetails,
    required this.onApprove,
    required this.onReject,
    required this.onRequestReupload,
  });

  @override
  Widget build(BuildContext context) {
    final tab = _kTabs[tabIndex];
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: FutureBuilder<List<dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('Error: ${snapshot.error}')))]);
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return ListView(
              children: [
                AdminEmptyState(
                  icon: tab.icon,
                  title: 'Nothing here',
                  subtitle: 'No ${tab.label.toLowerCase()} KYC submissions right now.',
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final k = items[i] as Map<String, dynamic>;
              return AdminReveal(
                index: i,
                child: _KYCCard(
                  kyc: k,
                  tabIndex: tabIndex,
                  onTap: () => onOpenDetails(k),
                  onApprove: () => onApprove(k['user_id']),
                  onReject: () => onReject(k['user_id']),
                  onRequestReupload: () => onRequestReupload(k['user_id']),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _KYCCard extends StatelessWidget {
  final Map<String, dynamic> kyc;
  final int tabIndex;
  final VoidCallback onTap;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onRequestReupload;

  const _KYCCard({
    required this.kyc,
    required this.tabIndex,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
    required this.onRequestReupload,
  });

  @override
  Widget build(BuildContext context) {
    final name = kyc['user_full_name'] as String? ?? 'User ${kyc['user_id']}';
    final role = (kyc['user_role'] as String? ?? '').toUpperCase();
    final company = kyc['company_name'] as String?;
    final country = kyc['company_country'] as String?;
    final avatarUrl = kyc['user_avatar_url'] as String?;
    final createdAt = kyc['created_at'] as String?;
    final isPending = tabIndex == 0;

    return AdminCard(
      margin: const EdgeInsets.only(bottom: 14),
      onTap: onTap,
      accent: const Color(0xFF7C3AED),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (role.isNotEmpty) _Tag(role),
                            if (company != null && company.isNotEmpty) _Tag(company),
                            if (country != null && country.isNotEmpty) _Tag(country),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(status: kyc['status'] as String? ?? ''),
                ],
              ),
              if (createdAt != null) ...[
                const SizedBox(height: 10),
                Text('Submitted: ${_formatDate(createdAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View Details'),
                    ),
                  ),
                  if (isPending) ...[
                    const SizedBox(width: 8),
                    IconButton(onPressed: onReject, icon: const Icon(Icons.close), color: AppColors.error, tooltip: 'Reject'),
                    IconButton(onPressed: onRequestReupload, icon: const Icon(Icons.upload_file_outlined), color: AppColors.primary, tooltip: 'Request Re-upload'),
                    IconButton(onPressed: onApprove, icon: const Icon(Icons.check_circle), color: AppColors.success, tooltip: 'Approve'),
                  ],
                ],
              ),
            ],
          ),
    );
  }
}

String _formatDate(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
      child: Text(text, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    switch (status) {
      case 'verified':
        color = AppColors.success;
        label = 'Approved';
        break;
      case 'rejected':
        color = AppColors.error;
        label = 'Rejected';
        break;
      case 'needs_reupload':
        color = AppColors.warning;
        label = 'Re-upload';
        break;
      default:
        color = AppColors.textSecondary;
        label = 'Pending';
    }
    return AdminStatusBadge(label: label, color: color);
  }
}

/// Full detail view for a single KYC submission: every applicant field, every declared
/// number, and every uploaded document opened via the full-screen [_DocumentViewerScreen].
class _KYCDetailScreen extends StatelessWidget {
  final Map<String, dynamic> kyc;
  final int tabIndex;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onRequestReupload;

  const _KYCDetailScreen({
    required this.kyc,
    required this.tabIndex,
    required this.onApprove,
    required this.onReject,
    required this.onRequestReupload,
  });

  @override
  Widget build(BuildContext context) {
    final docs = <MapEntry<String, String>>[
      if (kyc['pan_doc_url'] != null) MapEntry('PAN', kyc['pan_doc_url']),
      if (kyc['gst_doc_url'] != null) MapEntry('GST', kyc['gst_doc_url']),
      if (kyc['iec_doc_url'] != null) MapEntry('IEC', kyc['iec_doc_url']),
      if (kyc['address_doc_url'] != null) MapEntry('Address Proof', kyc['address_doc_url']),
      if (kyc['bank_doc_url'] != null) MapEntry('Bank Proof', kyc['bank_doc_url']),
    ];
    final isPending = tabIndex == 0;

    return Scaffold(
      appBar: const AdminGradientAppBar(title: 'KYC Details'),
      body: AdminPageBackground(
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DetailSection(title: 'Applicant', rows: [
            ('Name', kyc['user_full_name'] as String? ?? '—'),
            ('User ID', kyc['user_id'] as String? ?? '—'),
            ('Role', (kyc['user_role'] as String? ?? '—').toUpperCase()),
            ('Company', kyc['company_name'] as String? ?? '—'),
            ('Email', kyc['user_email'] as String? ?? '—'),
            ('Phone', kyc['user_phone'] as String? ?? '—'),
            ('Country', kyc['company_country'] as String? ?? '—'),
          ]),
          const SizedBox(height: 16),
          _DetailSection(title: 'Declared Numbers', rows: [
            ('PAN', kyc['pan_number'] as String? ?? '—'),
            ('GST', kyc['gst_number'] as String? ?? '—'),
            ('IEC', kyc['iec_code'] as String? ?? '—'),
            ('Business License', kyc['business_license'] as String? ?? '—'),
          ]),
          const SizedBox(height: 16),
          _DetailSection(title: 'Bank Details', rows: [
            ('Account Holder', kyc['bank_account_holder_name'] as String? ?? '—'),
            ('Account Number', kyc['bank_account_number'] as String? ?? '—'),
            ('IFSC Code', kyc['bank_ifsc'] as String? ?? '—'),
          ]),
          const SizedBox(height: 16),
          _DetailSection(title: 'Submission', rows: [
            ('Submitted', kyc['created_at'] != null ? _formatDate(kyc['created_at']) : '—'),
            ('Status', (kyc['status'] as String? ?? '—')),
            if (kyc['rejection_reason'] != null) ('Reason', kyc['rejection_reason'] as String),
          ]),
          if (docs.isNotEmpty) ...[
            const SizedBox(height: 20),
            const AdminSectionHeader(icon: Icons.folder_outlined, title: 'Uploaded Documents', color: Color(0xFF0EA5E9)),
            const SizedBox(height: 10),
            ...docs.map((d) => AdminCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  accent: const Color(0xFF0EA5E9),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _DocumentViewerScreen(title: d.key, url: d.value),
                  )),
                  child: Row(
                    children: [
                      const AdminIconBadge(icon: Icons.description_outlined, color: Color(0xFF0EA5E9), size: 36),
                      const SizedBox(width: 12),
                      Expanded(child: Text(d.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 24),
          if (isPending)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      onReject();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      onRequestReupload();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Re-upload'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      onApprove();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                  ),
                ),
              ],
            ),
        ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _DetailSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      accent: const Color(0xFF2563EB),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.primary)),
            const SizedBox(height: 10),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 130, child: Text(r.$1, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
                      Expanded(child: Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    ],
                  ),
                )),
          ],
        ),
    );
  }
}

/// Full-screen document viewer. Images render in-app (zoomable); everything else (PDFs
/// etc.) falls back to opening in the device's default viewer/browser.
class _DocumentViewerScreen extends StatelessWidget {
  final String title;
  final String url;
  const _DocumentViewerScreen({required this.title, required this.url});

  bool get _isImage {
    final lower = url.toLowerCase();
    return lower.contains('.jpg') || lower.contains('.jpeg') || lower.contains('.png') || lower.contains('.webp') || lower.contains('.gif');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open externally',
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: Center(
        child: _isImage
            ? InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null ? child : const CircularProgressIndicator(color: Colors.white),
                  errorBuilder: (context, error, stack) => const _ViewerFallback(),
                ),
              )
            : const _ViewerFallback(),
      ),
    );
  }
}

class _ViewerFallback extends StatelessWidget {
  const _ViewerFallback();
  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_outlined, size: 64, color: Colors.white70),
        SizedBox(height: 12),
        Text('Preview not available — use "Open externally".', style: TextStyle(color: Colors.white70)),
      ],
    );
  }
}
