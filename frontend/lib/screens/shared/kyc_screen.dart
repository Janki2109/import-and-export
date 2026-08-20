import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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
///
/// DEVELOPMENT-MODE POLICY: uploading a document is sufficient by itself — PAN/GST/IEC
/// numbers and bank account details are all optional free text, never required, and
/// nothing about OCR ever blocks submission. Admin verifies by reviewing the uploaded
/// document image directly, not by trusting a typed/extracted number.
///
/// OCR (Google ML Kit, on-device) still runs in the background as each document is
/// uploaded, purely as a convenience: if it finds a clean match for the number, it
/// fills the field in for you. If it doesn't, the field is simply left blank — there is
/// no failure message, no red error, and the user is never asked to "fix" anything. See
/// [_NumberFormat] / [_OcrIdField] for the (entirely optional) extraction logic, kept
/// around so real OCR/manual-entry validation can be turned on later without a rewrite.
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

  @override
  void dispose() {
    _panNumberCtrl.dispose();
    _gstNumberCtrl.dispose();
    _iecCodeCtrl.dispose();
    _businessLicenseCtrl.dispose();
    _bankAccountHolderNameCtrl.dispose();
    _bankAccountNumberCtrl.dispose();
    _bankIfscCtrl.dispose();
    super.dispose();
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
        bankDocUrl: docUrls['bank'] ?? _status?['bank_doc_url'],
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
  final Map<String, String?> _docUrls = {'pan': null, 'gst': null, 'iec': null, 'address': null, 'bank': null};

  bool get _hasAnyDocument {
    final hasFresh = _docUrls.values.any((v) => v != null);
    final hasExisting = (widget.status?['pan_doc_url'] != null) ||
        (widget.status?['gst_doc_url'] != null) ||
        (widget.status?['iec_doc_url'] != null) ||
        (widget.status?['address_doc_url'] != null) ||
        (widget.status?['bank_doc_url'] != null);
    return hasFresh || hasExisting;
  }

  void _handleSubmit() {
    if (!_hasAnyDocument) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload at least one document.'), backgroundColor: AppColors.error),
      );
      return;
    }
    widget.onSubmit(_docUrls);
  }

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
            _OcrIdField(
              controller: widget.panNumberCtrl,
              label: 'PAN Number',
              icon: Icons.badge_outlined,
              docLabel: 'PAN Document',
              format: _NumberFormat.pan,
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
            _OcrIdField(
              controller: widget.gstNumberCtrl,
              label: 'GST Number',
              icon: Icons.receipt_long_outlined,
              docLabel: 'GST Document',
              format: _NumberFormat.gst,
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
            _OcrIdField(
              controller: widget.iecCodeCtrl,
              label: 'IEC Code',
              icon: Icons.public_outlined,
              docLabel: 'IEC Document',
              // Post-2021, IEC = PAN, so the same 10-char pattern applies.
              format: _NumberFormat.pan,
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
              decoration: const InputDecoration(labelText: 'Business License (Logistics only, optional)', prefixIcon: Icon(Icons.home_work_outlined)),
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
            const Text(
              'Upload a cancelled cheque, passbook photo, or bank statement — that alone is enough. '
              'Filling in the details below is optional.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            _DocPicker(
              label: 'Bank Document (Cheque / Passbook / Statement)',
              existingUrl: widget.status?['bank_doc_url'],
              enabled: !isVerified,
              onUploaded: (url) => setState(() => _docUrls['bank'] = url),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: widget.bankAccountHolderNameCtrl,
              enabled: !isVerified,
              decoration: const InputDecoration(labelText: 'Account Holder Name (optional)', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: widget.bankAccountNumberCtrl,
              enabled: !isVerified,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Account Number (optional)', prefixIcon: Icon(Icons.account_balance_outlined)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: widget.bankIfscCtrl,
              enabled: !isVerified,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'IFSC Code (optional)', prefixIcon: Icon(Icons.pin_outlined)),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (!isVerified)
          ElevatedButton(
            onPressed: widget.submitting ? null : _handleSubmit,
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
      case 'needs_reupload':
        return _banner(
          icon: Icons.upload_file_outlined,
          color: AppColors.warning,
          title: 'Re-upload Requested',
          subtitle: rejectionReason != null ? 'Admin requested: $rejectionReason' : 'The admin has asked you to re-upload one or more documents.',
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

/// Fixed-width ID-number layout (PAN/IEC = 10 chars, GST = 15) — the shape OCR
/// extraction looks for once a matching pattern is being searched for. `digit` is true
/// where that position must be 0-9, false where it must be A-Z, null where either is
/// accepted (GST's entity-code and checksum characters). Not used for validation —
/// see the class doc comment: numbers are optional free text during development.
class _NumberFormat {
  final int length;
  final List<bool?> digitAt;
  final RegExp validate;

  const _NumberFormat({required this.length, required this.digitAt, required this.validate});

  static final pan = _NumberFormat(
    length: 10,
    digitAt: const [false, false, false, false, false, true, true, true, true, false],
    validate: RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$'),
  );

  static final gst = _NumberFormat(
    length: 15,
    digitAt: const [true, true, false, false, false, false, false, true, true, true, true, false, null, false, null],
    validate: RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
  );
}

/// A single ID-number field wired to its document photo. The field is always optional
/// and always editable — OCR is a pure convenience layer on top, never a gate: if it
/// finds a clean (or fuzzily-correctable) match in the uploaded photo it fills the
/// field in, and if it doesn't, the field is just left blank with no error shown.
class _OcrIdField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String docLabel;
  final _NumberFormat format;
  final String? existingUrl;
  final bool enabled;
  final void Function(String url) onUploaded;

  const _OcrIdField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.docLabel,
    required this.format,
    required this.onUploaded,
    this.existingUrl,
    this.enabled = true,
  });

  @override
  State<_OcrIdField> createState() => _OcrIdFieldState();
}

class _OcrIdFieldState extends State<_OcrIdField> {
  void _applyOcrResult(String rawText) {
    final match = _extractNumber(rawText, widget.format);
    if (!mounted || match == null) return;
    setState(() => widget.controller.text = match);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: '${widget.label} (optional)', prefixIcon: Icon(widget.icon)),
          // No validator: document upload alone is sufficient during development —
          // see the KYCScreen doc comment.
        ),
        const SizedBox(height: 10),
        _DocPicker(
          label: widget.docLabel,
          existingUrl: widget.existingUrl,
          enabled: widget.enabled,
          onUploaded: widget.onUploaded,
          onTextExtracted: _applyOcrResult,
        ),
      ],
    );
  }
}

/// Common OCR letter/digit misreads, keyed by the class we need at that position.
const _kOcrDigitFixes = {'O': '0', 'I': '1', 'L': '1', 'S': '5', 'B': '8', 'Z': '2', 'G': '6', 'Q': '0', 'D': '0'};
const _kOcrLetterFixes = {'0': 'O', '1': 'I', '5': 'S', '8': 'B', '2': 'Z', '6': 'G'};

/// Slides a [format.length]-wide window across the OCR text (stripped of
/// whitespace/punctuation) looking for a substring matching [format]. Tries an exact
/// match first, then retries with per-position correction of the most common OCR
/// letter/digit confusions. Returns null on no match — the caller treats that as "OCR
/// found nothing," which is a normal, unremarkable outcome, not a failure to surface.
String? _extractNumber(String rawText, _NumberFormat format) {
  final cleaned = rawText.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (cleaned.length < format.length) return null;

  for (var i = 0; i <= cleaned.length - format.length; i++) {
    final window = cleaned.substring(i, i + format.length);
    if (format.validate.hasMatch(window)) return window;
  }

  for (var i = 0; i <= cleaned.length - format.length; i++) {
    final window = cleaned.substring(i, i + format.length);
    final buf = StringBuffer();
    var changed = false;
    for (var p = 0; p < format.length; p++) {
      final ch = window[p];
      final wantDigit = format.digitAt[p];
      if (wantDigit == null) {
        buf.write(ch);
        continue;
      }
      final isDigit = RegExp(r'[0-9]').hasMatch(ch);
      if (isDigit == wantDigit) {
        buf.write(ch);
      } else {
        final fixed = wantDigit ? _kOcrDigitFixes[ch] : _kOcrLetterFixes[ch];
        if (fixed == null) {
          buf.write(ch);
        } else {
          buf.write(fixed);
          changed = true;
        }
      }
    }
    if (changed) {
      final corrected = buf.toString();
      if (format.validate.hasMatch(corrected)) return corrected;
    }
  }

  return null;
}

/// Picks an image (camera or gallery), uploads it to S3, and reports the resulting URL up.
/// If a document was already submitted previously, shows a "View" link for it instead of
/// a blank picker, so the user can see what's on file before choosing to replace it.
///
/// When [onTextExtracted] is supplied, also runs on-device OCR on the picked image in the
/// background and reports the recognized text up if any is found. This never affects the
/// upload: OCR success/failure is invisible to the user — the only status shown here is
/// upload progress and "Document uploaded successfully".
class _DocPicker extends StatefulWidget {
  final String label;
  final String? existingUrl;
  final bool enabled;
  final void Function(String url) onUploaded;
  final void Function(String text)? onTextExtracted;
  const _DocPicker({
    required this.label,
    this.existingUrl,
    this.enabled = true,
    required this.onUploaded,
    this.onTextExtracted,
  });

  @override
  State<_DocPicker> createState() => _DocPickerState();
}

class _DocPickerState extends State<_DocPicker> {
  final _picker = ImagePicker();
  final _uploadService = UploadService();
  Uint8List? _previewBytes;
  bool _uploading = false;
  String? _uploadedUrl;

  Future<void> _pickAndUpload() async {
    if (!widget.enabled) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    // XFile.readAsBytes() works on every platform (mobile file, web blob: URL alike) —
    // dart:io File does not, since a web XFile's "path" is a blob: URL it can't open.
    final bytes = await picked.readAsBytes();
    setState(() {
      _previewBytes = bytes;
      _uploading = true;
      _uploadedUrl = null;
    });

    // Fire-and-forget: OCR is a background convenience only. Errors are swallowed —
    // it must never surface a message or affect the upload/submit flow either way. Not
    // supported on web (google_mlkit_text_recognition is mobile-only), so skip there.
    if (widget.onTextExtracted != null && !kIsWeb) {
      _runOcr(File(picked.path)).catchError((_) {});
    }

    try {
      final url = await _uploadService.uploadBytes(
        category: 'kyc',
        bytes: bytes,
        fileName: picked.name,
        contentType: 'image/jpeg',
      );
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

  Future<void> _runOcr(File file) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFile(file));
      if (mounted && result.text.trim().isNotEmpty) {
        widget.onTextExtracted!(result.text);
      }
    } finally {
      await recognizer.close();
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
            if (_previewBytes != null)
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(_previewBytes!, height: 40, width: 40, fit: BoxFit.cover))
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
                        ? 'Document uploaded successfully'
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
