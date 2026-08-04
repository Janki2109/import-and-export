import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reference.dart';
import '../../services/freight_report_pdf.dart';
import '../../services/search_service.dart';

class FreightCalculatorScreen extends StatefulWidget {
  const FreightCalculatorScreen({super.key});
  @override
  State<FreightCalculatorScreen> createState() => _FreightCalculatorScreenState();
}

class _FreightCalculatorScreenState extends State<FreightCalculatorScreen> {
  final _formKey = GlobalKey<FormState>();
  String _mode = 'air';
  final _weightCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _packagesCtrl = TextEditingController(text: '1');
  final _originCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();
  final _searchService = SearchService();
  final _reportKey = GlobalKey();

  bool _insurance = false;
  bool _express = false;
  FreightEstimate? _result;
  String? _reportNumber;
  DateTime? _generatedAt;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _packagesCtrl.dispose();
    _originCtrl.dispose();
    _destinationCtrl.dispose();
    super.dispose();
  }

  // The estimate itself is untouched — same SearchService.calculateFreight() call, same
  // mode/weight/dimensions params, as before. Only the result presentation is redesigned.
  Future<void> _calculate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _searchService.calculateFreight(
        mode: _mode,
        weightKg: double.parse(_weightCtrl.text),
        lengthCm: double.tryParse(_lengthCtrl.text) ?? 0,
        widthCm: double.tryParse(_widthCtrl.text) ?? 0,
        heightCm: double.tryParse(_heightCtrl.text) ?? 0,
      );
      if (mounted) {
        setState(() {
          _result = result;
          _reportNumber = 'FRT-${DateTime.now().millisecondsSinceEpoch}';
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

  ({String transit, String recommended}) _transitInfo() {
    switch (_mode) {
      case 'air':
        return _express ? (transit: '1–3 Days', recommended: 'Priority Air Freight') : (transit: '3–7 Days', recommended: 'Standard Air Freight');
      case 'sea':
        return _express ? (transit: '15–25 Days', recommended: 'Express Sea (LCL Priority)') : (transit: '20–45 Days', recommended: 'Sea Freight (FCL/LCL)');
      case 'road':
        return _express ? (transit: '1–4 Days', recommended: 'Express Road Freight') : (transit: '2–10 Days', recommended: 'Standard Road Freight');
      default:
        return (transit: '—', recommended: '—');
    }
  }

  FreightReportPdfData _pdfData() {
    return FreightReportPdfData(
      reportNumber: _reportNumber ?? '',
      generatedAt: _generatedAt ?? DateTime.now(),
      mode: _mode,
      actualWeightKg: double.tryParse(_weightCtrl.text) ?? 0,
      packages: int.tryParse(_packagesCtrl.text) ?? 1,
      originCountry: _originCtrl.text.trim().isEmpty ? 'Not specified' : _originCtrl.text.trim(),
      destinationCountry: _destinationCtrl.text.trim().isEmpty ? 'Not specified' : _destinationCtrl.text.trim(),
      insurance: _insurance,
      express: _express,
      estimate: _result!,
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
      await Gal.putImageBytes(bytes, name: 'freight-estimate-${_reportNumber ?? DateTime.now().millisecondsSinceEpoch}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estimate Saved Successfully'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save image: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _downloadPdf() async {
    setState(() => _saving = true);
    try {
      final bytes = await buildFreightReportPdf(_pdfData());
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'freight-estimate-${_reportNumber ?? ''}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate PDF: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    final r = _result;
    if (r == null) return;
    final t = _transitInfo();
    final text = '''
Freight Estimate ${_reportNumber ?? ''}
Transport Mode: ${_mode[0].toUpperCase()}${_mode.substring(1)}
Actual Weight: ${_weightCtrl.text} kg
Chargeable Weight: ${r.chargeableWeightKg.toStringAsFixed(2)} kg
Estimated Transit Time: ${t.transit}

Estimated Freight: ₹${r.estimatedFreight.toStringAsFixed(2)}

Generated by ${AppConstants.appName}
''';
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Freight Calculator')),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: _result == null ? _buildForm() : _buildResult(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeaderCard(),
            const SizedBox(height: 20),
            Text('Transport Mode', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _TransportModeCard(mode: 'air', icon: Icons.flight_outlined, title: 'Air Freight', subtitle: 'Fast Delivery', eta: '1–7 Days', selected: _mode == 'air', onTap: () => setState(() => _mode = 'air')),
            const SizedBox(height: 10),
            _TransportModeCard(mode: 'sea', icon: Icons.directions_boat_outlined, title: 'Sea Freight', subtitle: 'Economical', eta: '20–45 Days', selected: _mode == 'sea', onTap: () => setState(() => _mode = 'sea')),
            const SizedBox(height: 10),
            _TransportModeCard(mode: 'road', icon: Icons.local_shipping_outlined, title: 'Road Freight', subtitle: 'Domestic / Regional', eta: '2–10 Days', selected: _mode == 'road', onTap: () => setState(() => _mode = 'road')),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('Shipment Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _weightCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Actual Weight (kg)', prefixIcon: Icon(Icons.scale_outlined)),
                      validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                    ),
                    _hint('Enter gross shipment weight.'),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: TextFormField(controller: _lengthCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'L (cm)'))),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: _widthCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'W (cm)'))),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: _heightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'H (cm)'))),
                      ],
                    ),
                    _hint('Dimensions — used for volumetric weight calculation (optional).'),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _packagesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Number of Packages', prefixIcon: Icon(Icons.widgets_outlined)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: TextFormField(controller: _originCtrl, decoration: const InputDecoration(labelText: 'Origin Country'))),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: _destinationCtrl, decoration: const InputDecoration(labelText: 'Destination Country'))),
                      ],
                    ),
                    _hint('Optional — shown on the estimate for reference.'),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _insurance,
                      onChanged: (v) => setState(() => _insurance = v),
                      title: const Text('Insurance Required'),
                      subtitle: const Text('Indicative only — contact us for a quote', style: TextStyle(fontSize: 11.5)),
                      activeThumbColor: AppColors.primary,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _express,
                      onChanged: (v) => setState(() => _express = v),
                      title: const Text('Express Delivery'),
                      subtitle: const Text('Adjusts the estimated transit time shown below', style: TextStyle(fontSize: 11.5)),
                      activeThumbColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _GradientButton(loading: _loading, onPressed: _calculate, label: 'Estimate Freight'),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
          ],
        ),
      ),
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
    );
  }

  Widget _buildResult() {
    final t = _transitInfo();
    return Column(
      key: const ValueKey('result'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: _reportKey,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ResultCard(
                      reportNumber: _reportNumber ?? '',
                      generatedAt: _generatedAt ?? DateTime.now(),
                      mode: _mode,
                      actualWeightKg: double.tryParse(_weightCtrl.text) ?? 0,
                      estimate: _result!,
                      transitTime: t.transit,
                      recommended: t.recommended,
                    ),
                    const SizedBox(height: 16),
                    _CostBreakdownCard(estimate: _result!, insurance: _insurance),
                    const SizedBox(height: 16),
                    const _ShipmentInfoCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
        _ActionBar(
          busy: _saving,
          onSaveImage: _saveAsImage,
          onDownloadPdf: _downloadPdf,
          onShare: _share,
          onNewCalculation: _newCalculation,
        ),
      ],
    );
  }
}

/// Premium header card below the app bar — quick summary of what this tool does.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.local_shipping_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Freight Cost Estimator', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Estimate shipping cost for Air, Sea and Road shipments.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _FeatureTick('Fast Estimate'),
              _FeatureTick('Volumetric Weight'),
              _FeatureTick('International Shipping'),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureTick extends StatelessWidget {
  final String label;
  const _FeatureTick(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 11, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// One transport-mode option card — animates its border/background when selected.
class _TransportModeCard extends StatelessWidget {
  final String mode;
  final IconData icon;
  final String title;
  final String subtitle;
  final String eta;
  final bool selected;
  final VoidCallback onTap;

  const _TransportModeCard({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.eta,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? AppColors.primary : Colors.grey.shade300, width: selected ? 1.6 : 1),
          boxShadow: selected ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 6))] : [],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: selected ? Colors.white : AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(Icons.schedule, size: 14, color: selected ? AppColors.primary : AppColors.textSecondary),
                const SizedBox(height: 2),
                Text(eta, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: selected ? AppColors.primary : AppColors.textSecondary)),
              ],
            ),
            const SizedBox(width: 10),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: selected ? 1 : 0,
              child: const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// Large gradient CTA with an animated loading state.
class _GradientButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  final String label;
  const _GradientButton({required this.loading, required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onPressed,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: loading
              ? const SizedBox(height: 22, width: 22, key: ValueKey('loading'), child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(label, key: const ValueKey('label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
        ),
      ),
    );
  }
}

/// Professional result summary card — transport mode, weights, estimated freight, transit time.
class _ResultCard extends StatelessWidget {
  final String reportNumber;
  final DateTime generatedAt;
  final String mode;
  final double actualWeightKg;
  final FreightEstimate estimate;
  final String transitTime;
  final String recommended;

  const _ResultCard({
    required this.reportNumber,
    required this.generatedAt,
    required this.mode,
    required this.actualWeightKg,
    required this.estimate,
    required this.transitTime,
    required this.recommended,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child),
      ),
      child: Container(
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
            Row(
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
                const Expanded(child: Text('Estimated Freight', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Estimate No.', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                    Text(reportNumber, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _stat('Transport Mode', mode[0].toUpperCase() + mode.substring(1), Icons.local_shipping_outlined)),
                Expanded(child: _stat('Actual Weight', '${actualWeightKg.toStringAsFixed(2)} kg', Icons.scale_outlined)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _stat('Chargeable Weight', '${estimate.chargeableWeightKg.toStringAsFixed(2)} kg', Icons.inventory_2_outlined)),
                Expanded(child: _stat('Transit Time', transitTime, Icons.schedule)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.star_outline, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Recommended: $recommended', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12.5))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Estimated Freight', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  Text('₹${estimate.estimatedFreight.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Icon(icon, size: 13, color: AppColors.textSecondary), const SizedBox(width: 5), Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))]),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      ],
    );
  }
}

/// Cost breakdown — green cells show the two figures the backend actually returns
/// (base freight from chargeable weight × rate, and the handling fee); anything the
/// backend doesn't compute is clearly marked rather than estimated on the client.
class _CostBreakdownCard extends StatelessWidget {
  final FreightEstimate estimate;
  final bool insurance;
  const _CostBreakdownCard({required this.estimate, required this.insurance});

  @override
  Widget build(BuildContext context) {
    final freightCharges = estimate.chargeableWeightKg * estimate.ratePerKg;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Cost Breakdown', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 12),
            _line('Base Freight', '${estimate.chargeableWeightKg.toStringAsFixed(2)} kg × ₹${estimate.ratePerKg.toStringAsFixed(2)}/kg', '₹${freightCharges.toStringAsFixed(2)}', known: true),
            _line('Handling Charges', 'Flat fee for this mode', '₹${estimate.baseHandlingFee.toStringAsFixed(2)}', known: true),
            _line('Fuel Surcharge', 'Not included in this estimate', 'N/A', known: false),
            _line('Documentation Charges', 'Not included in this estimate', 'N/A', known: false),
            _line('Insurance', insurance ? 'Indicative — contact for quote' : 'Not selected', insurance ? '—' : 'N/A', known: false),
            _line('Taxes', 'Not included in this estimate', 'N/A', known: false),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Freight', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text('₹${estimate.estimatedFreight.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String note, String value, {required bool known}) {
    final color = known ? AppColors.accent : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: known ? AppColors.textPrimary : AppColors.textSecondary)),
                Text(note, style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.85), fontSize: 10.5)),
              ],
            ),
          ),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: color)),
        ],
      ),
    );
  }
}

/// Expandable "Shipment Information" card — static reference info, no calculation involved.
class _ShipmentInfoCard extends StatefulWidget {
  const _ShipmentInfoCard();
  @override
  State<_ShipmentInfoCard> createState() => _ShipmentInfoCardState();
}

class _ShipmentInfoCardState extends State<_ShipmentInfoCard> {
  bool _expanded = true;

  static const _items = [
    ('Packaging Tips', 'Use sturdy, water-resistant packaging and cushion fragile items to prevent transit damage.'),
    ('Restricted Goods Notice', 'Some goods require additional permits or are banned for export/import — check trade policies before shipping.'),
    ('Dangerous Goods Warning', 'Hazardous materials must be declared and packed per IATA/IMDG regulations — undeclared hazmat can void insurance.'),
    ('Transit Information', 'Transit times shown are estimates; customs clearance and peak-season congestion can add delays.'),
    ('Customs Clearance Note', 'Ensure your HS code, invoice, and packing list are accurate — mismatches are the most common cause of customs holds.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Shipment Information', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: _items
                          .map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                          const SizedBox(height: 2),
                                          Text(item.$2, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Bottom action row — responsive 2x2 wrap on phones, single row on wide/tablet layouts.
class _ActionBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onSaveImage;
  final VoidCallback onDownloadPdf;
  final VoidCallback onShare;
  final VoidCallback onNewCalculation;

  const _ActionBar({
    required this.busy,
    required this.onSaveImage,
    required this.onDownloadPdf,
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
              _actionButton(Icons.bookmark_border, 'Save Estimate', onSaveImage, AppColors.secondary),
              _actionButton(Icons.picture_as_pdf_outlined, 'Download PDF', onDownloadPdf, AppColors.error),
              _actionButton(Icons.share_outlined, 'Share Estimate', onShare, AppColors.accent),
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
