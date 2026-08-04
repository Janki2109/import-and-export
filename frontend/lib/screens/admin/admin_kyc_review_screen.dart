import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';

/// Admin queue for reviewing KYC submissions — shows the applicant's declared numbers
/// (PAN/GST/IEC) alongside every document they uploaded, so the admin can open each doc
/// (image or PDF, served straight from S3) before approving or rejecting.
class AdminKYCReviewScreen extends StatefulWidget {
  const AdminKYCReviewScreen({super.key});
  @override
  State<AdminKYCReviewScreen> createState() => _AdminKYCReviewScreenState();
}

class _AdminKYCReviewScreenState extends State<AdminKYCReviewScreen> {
  final _adminService = AdminService();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _adminService.listPendingKYC();
  }

  void _refresh() => setState(() => _future = _adminService.listPendingKYC());

  Future<void> _approve(String userId) async {
    try {
      await _adminService.approveKYC(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KYC approved — the user has been notified.'), backgroundColor: AppColors.success),
        );
      }
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _reject(String userId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject KYC'),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || reasonCtrl.text.trim().isEmpty) {
      reasonCtrl.dispose();
      return;
    }
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    try {
      await _adminService.rejectKYC(userId, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KYC rejected — the user has been notified.'), backgroundColor: AppColors.warning),
        );
      }
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _openDoc(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open document.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending KYC Approvals')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.task_alt, size: 34, color: AppColors.success),
                      ),
                      const SizedBox(height: 16),
                      const Text('All caught up', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 6),
                      const Text('No pending KYC submissions right now.', style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final k = items[i];
                final docs = <MapEntry<String, String>>[
                  if (k['pan_doc_url'] != null) MapEntry('PAN Document', k['pan_doc_url']),
                  if (k['gst_doc_url'] != null) MapEntry('GST Document', k['gst_doc_url']),
                  if (k['iec_doc_url'] != null) MapEntry('IEC Document', k['iec_doc_url']),
                  if (k['address_doc_url'] != null) MapEntry('Address Proof', k['address_doc_url']),
                ];
                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.person_outline, color: AppColors.primary),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('User ${k['user_id']}',
                                  style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (k['pan_number'] != null) _InfoChip(label: 'PAN', value: k['pan_number']),
                            if (k['gst_number'] != null) _InfoChip(label: 'GST', value: k['gst_number']),
                            if (k['iec_code'] != null) _InfoChip(label: 'IEC', value: k['iec_code']),
                            if (k['business_license'] != null) _InfoChip(label: 'License', value: k['business_license']),
                          ],
                        ),
                        if (docs.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Text('Documents', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: docs
                                .map((d) => OutlinedButton.icon(
                                      onPressed: () => _openDoc(d.value),
                                      icon: const Icon(Icons.description_outlined, size: 16),
                                      label: Text(d.key, style: const TextStyle(fontSize: 12.5)),
                                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                    ))
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _reject(k['user_id']),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Reject'),
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _approve(k['user_id']),
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
              },
            );
          },
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(color: AppColors.textSecondary)),
            TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
