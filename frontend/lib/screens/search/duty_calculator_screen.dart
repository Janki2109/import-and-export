import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reference.dart';
import '../../services/duty_report_pdf.dart';
import '../../services/search_service.dart';

class DutyCalculatorScreen extends StatefulWidget {
  const DutyCalculatorScreen({super.key});
  @override
  State<DutyCalculatorScreen> createState() => _DutyCalculatorScreenState();
}

class _DutyCalculatorScreenState extends State<DutyCalculatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hsCodeCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _productNameCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _searchService = SearchService();
  final _reportKey = GlobalKey();

  DutyBreakdown? _result;
  String? _reportNumber;
  DateTime? _generatedAt;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _hsCodeCtrl.dispose();
    _valueCtrl.dispose();
    _productNameCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  // The duty math itself is untouched — same SearchService.calculateDuty() call as before.
  // Only the result presentation below has been redesigned into a full report.
  Future<void> _calculate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _searchService.calculateDuty(
        hsCode: _hsCodeCtrl.text.trim(),
        assessableValue: double.parse(_valueCtrl.text),
      );
      if (mounted) {
        setState(() {
          _result = result;
          _reportNumber = 'DCR-${DateTime.now().millisecondsSinceEpoch}';
          _generatedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _newCalculation() {
    setState(() {
      _result = null;
      _error = null;
      _reportNumber = null;
      _generatedAt = null;
    });
  }

  DutyReportPdfData _pdfData() {
    return DutyReportPdfData(
      reportNumber: _reportNumber ?? '',
      generatedAt: _generatedAt ?? DateTime.now(),
      hsCode: _hsCodeCtrl.text.trim(),
      productName: _productNameCtrl.text.trim().isEmpty ? 'Not specified' : _productNameCtrl.text.trim(),
      importCountry: _countryCtrl.text.trim().isEmpty ? 'Not specified' : _countryCtrl.text.trim(),
      breakdown: _result!,
    );
  }

  Future<void> _saveAsImage() async {
    setState(() => _saving = true);
    try {
      final boundary = _reportKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      await Gal.requestAccess();
      await Gal.putImageBytes(bytes, name: 'duty-report-${_reportNumber ?? DateTime.now().millisecondsSinceEpoch}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report Saved Successfully'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save image: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAsPdf() async {
    setState(() => _saving = true);
    try {
      final bytes = await buildDutyReportPdf(_pdfData());
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'duty-report-${_reportNumber ?? ''}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate PDF: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    final r = _result;
    if (r == null) return;
    final text = '''
Customs Duty Report ${_reportNumber ?? ''}
HS Code: ${_hsCodeCtrl.text.trim()}
Product: ${_productNameCtrl.text.trim().isEmpty ? 'Not specified' : _productNameCtrl.text.trim()}
Import Country: ${_countryCtrl.text.trim().isEmpty ? 'Not specified' : _countryCtrl.text.trim()}

Assessable Value: Rs. ${r.assessableValue.toStringAsFixed(2)}
Basic Customs Duty: Rs. ${r.basicCustomsDuty.toStringAsFixed(2)}
Social Welfare Surcharge: Rs. ${r.socialWelfareSurcharge.toStringAsFixed(2)}
IGST: Rs. ${r.igst.toStringAsFixed(2)}
Total Duty Payable: Rs. ${r.totalDutyPayable.toStringAsFixed(2)}
Total Landed Cost: Rs. ${r.totalLandedValue.toStringAsFixed(2)}

Generated by ${AppConstants.appName}
''';
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Duty Calculator')),
      body: SafeArea(
        child: _result == null ? _buildForm() : _buildReport(),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _hsCodeCtrl,
              decoration: const InputDecoration(labelText: 'HS Code (e.g. 8517.13)', prefixIcon: Icon(Icons.qr_code_2_outlined)),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _productNameCtrl,
              decoration: const InputDecoration(labelText: 'Product Name (optional, shown on report)', prefixIcon: Icon(Icons.inventory_2_outlined)),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _countryCtrl,
              decoration: const InputDecoration(labelText: 'Import Country (optional, shown on report)', prefixIcon: Icon(Icons.public_outlined)),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _valueCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Assessable Value (₹)', prefixIcon: Icon(Icons.currency_rupee)),
              validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _calculate,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Calculate Duty'),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
          ],
        ),
      ),
    );
  }

  Widget _buildReport() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: RepaintBoundary(
                key: _reportKey,
                child: _DutyReportCard(
                  reportNumber: _reportNumber ?? '',
                  generatedAt: _generatedAt ?? DateTime.now(),
                  hsCode: _hsCodeCtrl.text.trim(),
                  productName: _productNameCtrl.text.trim().isEmpty ? 'Not specified' : _productNameCtrl.text.trim(),
                  importCountry: _countryCtrl.text.trim().isEmpty ? 'Not specified' : _countryCtrl.text.trim(),
                  breakdown: _result!,
                ),
              ),
            ),
          ),
        ),
        _ActionBar(
          busy: _saving,
          onSaveImage: _saveAsImage,
          onSavePdf: _saveAsPdf,
          onShare: _share,
          onNewCalculation: _newCalculation,
        ),
      ],
    );
  }
}

/// Row of four action buttons pinned under the report — responsive 2x2 wrap on narrow
/// screens, single row on wide/tablet layouts.
class _ActionBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onSaveImage;
  final VoidCallback onSavePdf;
  final VoidCallback onShare;
  final VoidCallback onNewCalculation;

  const _ActionBar({
    required this.busy,
    required this.onSaveImage,
    required this.onSavePdf,
    required this.onShare,
    required this.onNewCalculation,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 480;
            final buttons = [
              _actionButton(Icons.image_outlined, 'Save as Image', onSaveImage, AppColors.secondary),
              _actionButton(Icons.picture_as_pdf_outlined, 'Save as PDF', onSavePdf, AppColors.error),
              _actionButton(Icons.share_outlined, 'Share', onShare, AppColors.accent),
              _actionButton(Icons.refresh, 'New Calculation', onNewCalculation, AppColors.primary),
            ];
            if (isWide) {
              return Row(children: buttons.map((b) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: b))).toList());
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: buttons.map((b) => SizedBox(width: (constraints.maxWidth - 8) / 2, child: b)).toList(),
            );
          },
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap, Color color) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
    );
  }
}

/// The report itself — an ICEGATE-style customs duty worksheet: header with logo/report
/// number/date, green "input" cells for shipment details, orange "calculation" cells for
/// each duty component with its formula, and a blue total summary at the bottom.
class _DutyReportCard extends StatelessWidget {
  final String reportNumber;
  final DateTime generatedAt;
  final String hsCode;
  final String productName;
  final String importCountry;
  final DutyBreakdown breakdown;

  const _DutyReportCard({
    required this.reportNumber,
    required this.generatedAt,
    required this.hsCode,
    required this.productName,
    required this.importCountry,
    required this.breakdown,
  });

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    final bcdPercent = b.assessableValue > 0 ? (b.basicCustomsDuty / b.assessableValue * 100) : 0;
    final igstBase = b.assessableValue + b.basicCustomsDuty + b.socialWelfareSurcharge;
    final igstPercent = igstBase > 0 ? (b.igst / igstBase * 100) : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Header: logo, title, report number, date/time ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('OBEI', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customs Duty Calculation Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(AppConstants.appName, style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Report No.', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                  Text(reportNumber, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(_formatDateTime(generatedAt), style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // ---- Shipment details: green "input" section ----
          _sectionLabel('SHIPMENT DETAILS', AppColors.success),
          const SizedBox(height: 8),
          _greenCell([
            _kv('HS Code', hsCode),
            _kv('Product Name', productName),
            _kv('Import Country', importCountry),
            _kv('CIF / Assessable Value', '₹${b.assessableValue.toStringAsFixed(2)}'),
            _kv('Landing Charges', 'Included in assessable value'),
          ]),

          const SizedBox(height: 20),

          // ---- Duty calculation: orange "computed" section with formulas ----
          _sectionLabel('DUTY CALCULATION', AppColors.accent),
          const SizedBox(height: 8),
          _orangeCalcRow('Basic Customs Duty (BCD)', 'Assessable Value × ${bcdPercent.toStringAsFixed(1)}%', b.basicCustomsDuty),
          _orangeCalcRow('Social Welfare Surcharge', 'BCD × 10%', b.socialWelfareSurcharge),
          _naRow('Anti-Dumping Duty', 'Not applicable to this HS code'),
          _naRow('Safeguard Duty', 'Not applicable to this HS code'),
          _naRow('Compensation Cess', 'Not applicable to this HS code'),
          _orangeCalcRow('IGST', '(Assessable Value + BCD + SWS) × ${igstPercent.toStringAsFixed(1)}%', b.igst),
          _naRow('GST Compensation Cess', 'Not applicable to this HS code'),

          const SizedBox(height: 16),

          // ---- Totals: premium blue summary ----
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Duty Payable', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    Text('₹${b.totalDutyPayable.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(color: Colors.white.withValues(alpha: 0.3), height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Landed Cost', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('₹${b.totalLandedValue.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            'This is a system-generated estimate for planning purposes only. Verify final classification and duty with a licensed customs broker before filing.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Row(
      children: [
        Container(width: 4, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.4)),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _greenCell(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.success.withValues(alpha: 0.25))),
      child: Column(children: children),
    );
  }

  Widget _orangeCalcRow(String label, String formula, double value) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.accent.withValues(alpha: 0.25))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Text('₹${value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.accent)),
            ],
          ),
          const SizedBox(height: 3),
          Text(formula, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _naRow(String label, String note) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.textSecondary)),
                Text(note, style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.8), fontSize: 10)),
              ],
            ),
          ),
          const Text('N/A', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${t.day}/${t.month}/${t.year}, $h:$m';
  }
}
