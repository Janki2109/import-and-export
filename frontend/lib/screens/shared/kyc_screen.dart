import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/kyc_service.dart';
import '../../services/upload_service.dart';

/// KYC submission — shared across all three roles (importer/exporter/logistics all
/// need KYC per the spec). Each document is captured/picked with image_picker, uploaded
/// to S3 via a presigned URL, then the resulting URL is submitted with /kyc/submit.
/// Doubles as the onboarding step (Create Company -> KYC -> Dashboard) and as a
/// later editable screen from the dashboard menu.
class KYCScreen extends ConsumerStatefulWidget {
  const KYCScreen({super.key});
  @override
  ConsumerState<KYCScreen> createState() => _KYCScreenState();
}

class _KYCScreenState extends ConsumerState<KYCScreen> {
  final _kycService = KYCService();
  final _panNumberCtrl = TextEditingController();
  final _gstNumberCtrl = TextEditingController();
  final _iecCodeCtrl = TextEditingController();
  final _businessLicenseCtrl = TextEditingController();
  final _bankAccountHolderNameCtrl = TextEditingController();
  final _bankAccountNumberCtrl = TextEditingController();
  final _bankIfscCtrl = TextEditingController();

  Map<String, dynamic>? _status;
  bool _loadingStatus = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _kycService.getMyStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _panNumberCtrl.text = status['pan_number'] ?? '';
          _gstNumberCtrl.text = status['gst_number'] ?? '';
          _iecCodeCtrl.text = status['iec_code'] ?? '';
          _businessLicenseCtrl.text = status['business_license'] ?? '';
          _bankAccountHolderNameCtrl.text = status['bank_account_holder_name'] ?? '';
          _bankAccountNumberCtrl.text = status['bank_account_number'] ?? '';
          _bankIfscCtrl.text = status['bank_ifsc'] ?? '';
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<void> _submit(Map<String, String?> docUrls) async {
    setState(() => _submitting = true);
    try {
      await _kycService.submit(
        panNumber: _panNumberCtrl.text.trim().isEmpty ? null : _panNumberCtrl.text.trim(),
        gstNumber: _gstNumberCtrl.text.trim().isEmpty ? null : _gstNumberCtrl.text.trim(),
        iecCode: _iecCodeCtrl.text.trim().isEmpty ? null : _iecCodeCtrl.text.trim(),
        businessLicense: _businessLicenseCtrl.text.trim().isEmpty ? null : _businessLicenseCtrl.text.trim(),
        panDocUrl: docUrls['pan'] ?? _status?['pan_doc_url'],
        gstDocUrl: docUrls['gst'] ?? _status?['gst_doc_url'],
        iecDocUrl: docUrls['iec'] ?? _status?['iec_doc_url'],
        addressDocUrl: docUrls['address'] ?? _status?['address_doc_url'],
        bankAccountHolderName: _bankAccountHolderNameCtrl.text.trim().isEmpty ? null : _bankAccountHolderNameCtrl.text.trim(),
        bankAccountNumber: _bankAccountNumberCtrl.text.trim().isEmpty ? null : _bankAccountNumberCtrl.text.trim(),
        bankIfsc: _bankIfscCtrl.text.trim().isEmpty ? null : _bankIfscCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KYC submitted, pending review.'), backgroundColor: AppColors.success),
        );
        _loadStatus();
        // If this was the onboarding step, flips kycSubmitted -> true so GoRouter's
        // redirect sends the user on to their dashboard.
        await ref.read(authProvider).refreshOnboardingStatus();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KYC Verification')),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: _KYCForm(
                  status: _status,
                  panNumberCtrl: _panNumberCtrl,
                  gstNumberCtrl: _gstNumberCtrl,
                  iecCodeCtrl: _iecCodeCtrl,
                  businessLicenseCtrl: _businessLicenseCtrl,
                  bankAccountHolderNameCtrl: _bankAccountHolderNameCtrl,
                  bankAccountNumberCtrl: _bankAccountNumberCtrl,
                  bankIfscCtrl: _bankIfscCtrl,
                  submitting: _submitting,
                  onSubmit: _submit,
                ),
              ),
            ),
    );
  }
}

class _KYCForm extends StatefulWidget {
  final Map<String, dynamic>? status;
  final TextEditingController panNumberCtrl;
  final TextEditingController gstNumberCtrl;
  final TextEditingController iecCodeCtrl;
  final TextEditingController businessLicenseCtrl;
  final TextEditingController bankAccountHolderNameCtrl;
  final TextEditingController bankAccountNumberCtrl;
  final TextEditingController bankIfscCtrl;
  final bool submitting;
  final void Function(Map<String, String?> docUrls) onSubmit;

  const _KYCForm({
    required this.status,
    required this.panNumberCtrl,
    required this.gstNumberCtrl,
    required this.iecCodeCtrl,
    required this.businessLicenseCtrl,
    required this.bankAccountHolderNameCtrl,
    required this.bankAccountNumberCtrl,
    required this.bankIfscCtrl,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  State<_KYCForm> createState() => _KYCFormState();
}

class _KYCFormState extends State<_KYCForm> {
  final Map<String, String?> _docUrls = {'pan': null, 'gst': null, 'iec': null, 'address': null};

  @override
  Widget build(BuildContext context) {
    final status = widget.status?['status'] as String?;
    final isVerified = status == 'verified';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusBanner(status: status, rejectionReason: widget.status?['rejection_reason']),
        const SizedBox(height: 20),
        _SectionCard(
          icon: Icons.badge_outlined,
          title: 'PAN Details',
          children: [
            TextFormField(
              controller: widget.panNumberCtrl,
              enabled: !isVerified,
              decoration: const InputDecoration(labelText: 'PAN Number', prefixIcon: Icon(Icons.badge_outlined)),
            ),
            const SizedBox(height: 10),
            _DocPicker(
              label: 'PAN Document',
              existingUrl: widget.status?['pan_doc_url'],
              enabled: !isVerified,
              onUploaded: (url) => setState(() => _docUrls['pan'] = url),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.receipt_long_outlined,
          title: 'GST Details',
          children: [
            TextFormField(
              controller: widget.gstNumberCtrl,
              enabled: !isVerified,
              decoration: const InputDecoration(labelText: 'GST Number', prefixIcon: Icon(Icons.receipt_long_outlined)),
            ),
            const SizedBox(height: 10),
            _DocPicker(
              label: 'GST Document',
              existingUrl: widget.status?['gst_doc_url'],
              enabled: !isVerified,
              onUploaded: (url) => setState(() => _docUrls['gst'] = url),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.public_outlined,
          title: 'Import-Export Code (IEC)',
          children: [
            TextFormField(
              controller: widget.iecCodeCtrl,
              enabled: !isVerified,
              decoration: const InputDecoration(labelText: 'IEC Code', prefixIcon: Icon(Icons.public_outlined)),
            ),
            const SizedBox(height: 10),
            _DocPicker(
              label: 'IEC Document',
              existingUrl: widget.status?['iec_doc_url'],
              enabled: !isVerified,
              onUploaded: (url) => setState(() => _docUrls['iec'] = url),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.home_work_outlined,
          title: 'Business & Address',
          children: [
            TextFormField(
              controller: widget.businessLicenseCtrl,
              enabled: !isVerified,
              decoration: const InputDecoration(labelText: 'Business License (Logistics only)', prefixIcon: Icon(Icons.home_work_outlined)),
            ),
            const SizedBox(height: 10),
            _DocPicker(
              label: 'Address Proof',
              existingUrl: widget.status?['address_doc_url'],
              enabled: !isVerified,
              onUploaded: (url) => setState(() => _docUrls['address'] = url),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.account_balance_outlined,
          title: 'Payout Bank Account',
          children: [
            TextFormField(
              controller: widget.bankAccountHolderNameCtrl,
              enabled: !isVerified,
              decoration: const InputDecoration(labelText: 'Account Holder Name', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: widget.bankAccountNumberCtrl,
              enabled: !isVerified,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Account Number', prefixIcon: Icon(Icons.account_balance_outlined)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: widget.bankIfscCtrl,
              enabled: !isVerified,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'IFSC Code', prefixIcon: Icon(Icons.pin_outlined)),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (!isVerified)
          ElevatedButton(
            onPressed: widget.submitting ? null : () => widget.onSubmit(_docUrls),
            child: widget.submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(status == null || status == 'pending' ? 'Submit KYC' : 'Resubmit KYC'),
          ),
      ],
    );
  }
}

/// Status banner at the top — icon + label, colored by status, with the admin's
/// rejection reason surfaced inline when applicable so the user knows what to fix.
class _StatusBanner extends StatelessWidget {
  final String? status;
  final String? rejectionReason;
  const _StatusBanner({required this.status, this.rejectionReason});

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return _banner(
        icon: Icons.info_outline,
        color: AppColors.textSecondary,
        title: 'Complete your KYC',
        subtitle: 'Submit your documents below to unlock full platform access.',
      );
    }
    switch (status) {
      case 'verified':
        return _banner(icon: Icons.verified_outlined, color: AppColors.success, title: 'KYC Verified', subtitle: "You're all set — full access unlocked.");
      case 'rejected':
        return _banner(
          icon: Icons.error_outline,
          color: AppColors.error,
          title: 'KYC Rejected',
          subtitle: rejectionReason != null ? 'Reason: $rejectionReason. Please fix and resubmit.' : 'Please review and resubmit your documents.',
        );
      case 'submitted':
      default:
        return _banner(
          icon: Icons.hourglass_top_outlined,
          color: AppColors.warning,
          title: 'Under Review',
          subtitle: 'Your documents were submitted and are awaiting admin review.',
        );
    }
  }

  Widget _banner({required IconData icon, required Color color, required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Groups a document type's number field + upload button under one titled card,
/// instead of a flat list of fields — makes the long form scannable.
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
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Picks an image (camera or gallery), uploads it to S3, and reports the resulting URL up.
/// If a document was already submitted previously, shows a "View" link for it instead of
/// a blank picker, so the user can see what's on file before choosing to replace it.
class _DocPicker extends StatefulWidget {
  final String label;
  final String? existingUrl;
  final bool enabled;
  final void Function(String url) onUploaded;
  const _DocPicker({required this.label, this.existingUrl, this.enabled = true, required this.onUploaded});

  @override
  State<_DocPicker> createState() => _DocPickerState();
}

class _DocPickerState extends State<_DocPicker> {
  final _picker = ImagePicker();
  final _uploadService = UploadService();
  File? _file;
  bool _uploading = false;
  String? _uploadedUrl;

  Future<void> _pickAndUpload() async {
    if (!widget.enabled) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _file = File(picked.path);
      _uploading = true;
      _uploadedUrl = null;
    });

    try {
      final url = await _uploadService.uploadFile(category: 'kyc', file: _file!, contentType: 'image/jpeg');
      if (mounted) {
        setState(() => _uploadedUrl = url);
        widget.onUploaded(url);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFreshUpload = _uploadedUrl != null;
    final hasExisting = !hasFreshUpload && widget.existingUrl != null;

    return InkWell(
      onTap: (_uploading || !widget.enabled) ? null : _pickAndUpload,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: hasFreshUpload || hasExisting ? AppColors.success : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (_file != null)
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(_file!, height: 40, width: 40, fit: BoxFit.cover))
            else
              Icon(
                hasExisting ? Icons.check_circle_outline : Icons.upload_file_outlined,
                color: hasExisting ? AppColors.success : AppColors.textSecondary,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _uploading
                    ? 'Uploading...'
                    : hasFreshUpload
                        ? '${widget.label} — uploaded'
                        : hasExisting
                            ? '${widget.label} — on file'
                            : widget.label,
                style: TextStyle(color: hasFreshUpload || hasExisting ? AppColors.success : AppColors.textPrimary),
              ),
            ),
            if (_uploading) const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            if (hasExisting && !_uploading)
              TextButton(
                onPressed: () => launchUrl(Uri.parse(widget.existingUrl!), mode: LaunchMode.externalApplication),
                child: const Text('View'),
              ),
            if (hasFreshUpload && !_uploading) const Icon(Icons.check_circle, color: AppColors.success, size: 20),
          ],
        ),
      ),
    );
  }
}
