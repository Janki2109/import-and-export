import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reference.dart';
import '../../services/landed_cost_report_pdf.dart';
import '../../services/search_service.dart';

class LandedCostCalculatorScreen extends StatefulWidget {
  const LandedCostCalculatorScreen({super.key});
  @override
  State<LandedCostCalculatorScreen> createState() => _LandedCostCalculatorScreenState();
}

class _LandedCostCalculatorScreenState extends State<LandedCostCalculatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hsCodeCtrl = TextEditingController();
  final _fobCtrl = TextEditingController();
  final _freightCtrl = TextEditingController(text: '0');
  final _insuranceCtrl = TextEditingController(text: '0');
  final _otherCtrl = TextEditingController(text: '0');
  final _packagesCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();
  final _searchService = SearchService();
  final _reportKey = GlobalKey();

  String _currency = 'INR';
  String _shippingMode = 'air';
  String _containerType = 'LCL';
  String _incoterm = 'FOB';
  bool _detailsExpanded = false;

  LandedCostBreakdown? _result;
  DutyBreakdown? _dutyDetail; // supplemental only — see _fetchDutyDetail()
  String? _productName;
  String? _reportNumber;
  DateTime? _generatedAt;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  static const _currencies = ['INR', 'USD', 'EUR', 'AED'];
  static const _incoterms = ['EXW', 'FOB', 'CIF', 'DAP', 'DDP'];

  @override
  void initState() {
    super.initState();
    // Live "Cost Summary Preview" + auto product-name lookup both just repaint on typing.
    for (final c in [_fobCtrl, _freightCtrl, _insuranceCtrl, _otherCtrl]) {
      c.addListener(_onLiveInputChanged);
    }
    _hsCodeCtrl.addListener(_onHsCodeChanged);
  }

  @override
  void dispose() {
    for (final c in [_fobCtrl, _freightCtrl, _insuranceCtrl, _otherCtrl]) {
      c.removeListener(_onLiveInputChanged);
    }
    _hsCodeCtrl.removeListener(_onHsCodeChanged);
    _hsDebounce?.cancel();
    _hsCodeCtrl.dispose();
    _fobCtrl.dispose();
    _freightCtrl.dispose();
    _insuranceCtrl.dispose();
    _otherCtrl.dispose();
    _packagesCtrl.dispose();
    _originCtrl.dispose();
    _destinationCtrl.dispose();
    super.dispose();
  }

  void _onLiveInputChanged() => setState(() {});

  DateTime? _lastHsLookup;
  Timer? _hsDebounce;
  void _onHsCodeChanged() {
    _hsDebounce?.cancel();
    final code = _hsCodeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _productName = null);
      return;
    }
    // Debounce the lookup so it fires once typing pauses instead of per-keystroke (existing
    // /search/hs-codes endpoint, already used elsewhere — no new backend call, purely a
    // display lookup).
    _hsDebounce = Timer(const Duration(milliseconds: 450), () => _lookupHsCode(code));
  }

  Future<void> _lookupHsCode(String code) async {
    final marker = DateTime.now();
    _lastHsLookup = marker;
    try {
      final matches = await _searchService.searchHSCodes(code);
      if (_lastHsLookup != marker || !mounted) return;
      final exact = matches.where((h) => h.code.toLowerCase() == code.toLowerCase());
      setState(() => _productName = exact.isNotEmpty ? exact.first.description : null);
    } catch (_) {
      // silent — this is a "nice to have" lookup, not required for calculation
    }
  }

  // The landed-cost math itself is untouched — same SearchService.calculateLandedCost()
  // call, same params, as before.
  Future<void> _calculate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _dutyDetail = null;
    });
    try {
      final result = await _searchService.calculateLandedCost(
        hsCode: _hsCodeCtrl.text.trim(),
        fobValue: double.parse(_fobCtrl.text),
        freight: double.tryParse(_freightCtrl.text) ?? 0,
        insurance: double.tryParse(_insuranceCtrl.text) ?? 0,
        otherCharges: double.tryParse(_otherCtrl.text) ?? 0,
      );
      if (mounted) {
        setState(() {
          _result = result;
          _reportNumber = 'LCR-${DateTime.now().millisecondsSinceEpoch}';
          _generatedAt = DateTime.now();
        });
      }
      await _fetchDutyDetail(result.cifValue);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Supplemental only: the backend's /calculators/duty endpoint (already used by the Duty
  /// Calculator screen) computes duty the same way internally when building landed cost —
  /// calling it again with the CIF value just exposes the BCD/SWS/IGST split for display.
  /// If it fails, the report simply shows the backend's authoritative combined `totalDuty`.
  Future<void> _fetchDutyDetail(double cifValue) async {
    try {
      final duty = await _searchService.calculateDuty(hsCode: _hsCodeCtrl.text.trim(), assessableValue: cifValue);
      if (mounted) setState(() => _dutyDetail = duty);
    } catch (_) {
      // breakdown rows fall back to "N/A" — total figures remain accurate regardless
    }
  }

  void _newCalculation() {
    setState(() {
      _result = null;
      _dutyDetail = null;
      _error = null;
      _reportNumber = null;
      _generatedAt = null;
    });
  }

  LandedCostReportPdfData _pdfData() {
    return LandedCostReportPdfData(
      reportNumber: _reportNumber ?? '',
      generatedAt: _generatedAt ?? DateTime.now(),
      hsCode: _hsCodeCtrl.text.trim(),
      productName: _productName ?? 'Not specified',
      breakdown: _result!,
      dutyDetail: _dutyDetail,
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
      await Gal.putImageBytes(bytes, name: 'landed-cost-report-${_reportNumber ?? DateTime.now().millisecondsSinceEpoch}');

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

  Future<void> _downloadPdf() async {
    setState(() => _saving = true);
    try {
      final bytes = await buildLandedCostReportPdf(_pdfData());
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'landed-cost-report-${_reportNumber ?? ''}.pdf');
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
Landed Cost Report ${_reportNumber ?? ''}
HS Code: ${_hsCodeCtrl.text.trim()}
${_productName != null ? 'Product: $_productName\n' : ''}
FOB Value: ₹${r.fobValue.toStringAsFixed(2)}
Freight: ₹${r.freight.toStringAsFixed(2)}
Insurance: ₹${r.insurance.toStringAsFixed(2)}
Other Charges: ₹${r.otherCharges.toStringAsFixed(2)}
Assessable / CIF Value: ₹${r.cifValue.toStringAsFixed(2)}
Total Duty: ₹${r.totalDuty.toStringAsFixed(2)}

Final Landed Cost: ₹${r.totalLandedCost.toStringAsFixed(2)}

Generated by ${AppConstants.appName}
''';
    await Share.share(text);
  }

  double get _fob => double.tryParse(_fobCtrl.text) ?? 0;
  double get _freight => double.tryParse(_freightCtrl.text) ?? 0;
  double get _insurance => double.tryParse(_insuranceCtrl.text) ?? 0;
  double get _other => double.tryParse(_otherCtrl.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Landed Cost Calculator')),
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
            _sectionTitle('Shipment Information', Icons.inventory_2_outlined),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _hsCodeCtrl,
                      decoration: const InputDecoration(labelText: 'HS Code (e.g. 8517.13)', prefixIcon: Icon(Icons.qr_code_2_outlined)),
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _productName != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
                                      const SizedBox(width: 6),
                                      Flexible(child: Text(_productName!, style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600))),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _fobCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'FOB Value (₹)', prefixIcon: Icon(Icons.currency_rupee)),
                            validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _currencyDropdown()),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(controller: _freightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Freight (₹)', prefixIcon: Icon(Icons.local_shipping_outlined))),
                    const SizedBox(height: 14),
                    TextFormField(controller: _insuranceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Insurance (₹)', prefixIcon: Icon(Icons.shield_outlined))),
                    const SizedBox(height: 14),
                    TextFormField(controller: _otherCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Other Charges (₹)', prefixIcon: Icon(Icons.receipt_long_outlined))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _AdditionalDetailsCard(
              expanded: _detailsExpanded,
              onToggle: () => setState(() => _detailsExpanded = !_detailsExpanded),
              originCtrl: _originCtrl,
              destinationCtrl: _destinationCtrl,
              packagesCtrl: _packagesCtrl,
              shippingMode: _shippingMode,
              onShippingModeChanged: (v) => setState(() => _shippingMode = v),
              containerType: _containerType,
              onContainerTypeChanged: (v) => setState(() => _containerType = v),
              incoterm: _incoterm,
              onIncotermChanged: (v) => setState(() => _incoterm = v),
              incoterms: _incoterms,
            ),
            const SizedBox(height: 16),
            _LiveSummaryCard(fob: _fob, freight: _freight, insurance: _insurance, other: _other, currency: _currency),
            const SizedBox(height: 20),
            _GradientButton(loading: _loading, onPressed: _calculate, label: 'Calculate Landed Cost'),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
          ],
        ),
      ),
    );
  }

  Widget _currencyDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _currency,
      decoration: const InputDecoration(labelText: 'Currency'),
      items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: (v) => setState(() => _currency = v ?? 'INR'),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }

  Widget _buildResult() {
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
                    _LandedCostReportCard(
                      reportNumber: _reportNumber ?? '',
                      generatedAt: _generatedAt ?? DateTime.now(),
                      hsCode: _hsCodeCtrl.text.trim(),
                      productName: _productName ?? 'Not specified',
                      breakdown: _result!,
                      dutyDetail: _dutyDetail,
                    ),
                    const SizedBox(height: 16),
                    _ExpandableBreakdownCard(
                      title: 'Cost Components',
                      icon: Icons.shopping_bag_outlined,
                      color: AppColors.success,
                      rows: [
                        ('FOB', _result!.fobValue),
                        ('Freight', _result!.freight),
                        ('Insurance', _result!.insurance),
                        ('Other Charges', _result!.otherCharges),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ExpandableBreakdownCard(
                      title: 'Duty Components',
                      icon: Icons.gavel_outlined,
                      color: AppColors.accent,
                      rows: [
                        if (_dutyDetail != null) ('BCD', _dutyDetail!.basicCustomsDuty),
                        if (_dutyDetail != null) ('SWS', _dutyDetail!.socialWelfareSurcharge),
                        if (_dutyDetail != null) ('IGST', _dutyDetail!.igst),
                        ('Total Duty', _result!.totalDuty),
                      ],
                      note: _dutyDetail == null ? 'Detailed BCD/SWS/IGST split unavailable — showing total duty only.' : null,
                    ),
                    const SizedBox(height: 12),
                    _ExpandableBreakdownCard(
                      title: 'Final Cost',
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppColors.primary,
                      rows: [('Total Import Cost', _result!.totalLandedCost)],
                      highlight: true,
                    ),
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

/// Premium header card below the app bar.
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
                child: const Icon(Icons.inventory_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Landed Cost Calculator', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Calculate the total import cost including FOB Value, Freight, Insurance, Other Charges and Customs Duty.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _FeatureTick('Accurate Cost Estimate'),
              _FeatureTick('Import Planning'),
              _FeatureTick('Customs Ready'),
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

/// Collapsible "Additional Shipment Details" — every field here is optional and purely
/// informational (shown on the report only); none of it is sent to the backend.
class _AdditionalDetailsCard extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final TextEditingController originCtrl;
  final TextEditingController destinationCtrl;
  final TextEditingController packagesCtrl;
  final String shippingMode;
  final ValueChanged<String> onShippingModeChanged;
  final String containerType;
  final ValueChanged<String> onContainerTypeChanged;
  final String incoterm;
  final ValueChanged<String> onIncotermChanged;
  final List<String> incoterms;

  const _AdditionalDetailsCard({
    required this.expanded,
    required this.onToggle,
    required this.originCtrl,
    required this.destinationCtrl,
    required this.packagesCtrl,
    required this.shippingMode,
    required this.onShippingModeChanged,
    required this.containerType,
    required this.onContainerTypeChanged,
    required this.incoterm,
    required this.onIncotermChanged,
    required this.incoterms,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Additional Shipment Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  const Text('Optional', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
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
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: TextFormField(controller: originCtrl, decoration: const InputDecoration(labelText: 'Origin Country'))),
                            const SizedBox(width: 8),
                            Expanded(child: TextFormField(controller: destinationCtrl, decoration: const InputDecoration(labelText: 'Destination Country'))),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Shipping Mode', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            _chip('Air', 'air', shippingMode, onShippingModeChanged, Icons.flight_outlined),
                            _chip('Sea', 'sea', shippingMode, onShippingModeChanged, Icons.directions_boat_outlined),
                            _chip('Road', 'road', shippingMode, onShippingModeChanged, Icons.local_shipping_outlined),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: containerType,
                                decoration: const InputDecoration(labelText: 'Container Type'),
                                items: const [
                                  DropdownMenuItem(value: 'LCL', child: Text('LCL')),
                                  DropdownMenuItem(value: 'FCL_20', child: Text('FCL 20 ft')),
                                  DropdownMenuItem(value: 'FCL_40', child: Text('FCL 40 ft')),
                                ],
                                onChanged: (v) => onContainerTypeChanged(v ?? 'LCL'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: TextFormField(controller: packagesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Package Count'))),
                          ],
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: incoterm,
                          decoration: const InputDecoration(labelText: 'Incoterm'),
                          items: incoterms.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                          onChanged: (v) => onIncotermChanged(v ?? 'FOB'),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, String selected, ValueChanged<String> onChanged, IconData icon) {
    final isSelected = selected == value;
    return ChoiceChip(
      label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: isSelected ? Colors.white : AppColors.textSecondary), const SizedBox(width: 4), Text(label)]),
      selected: isSelected,
      onSelected: (_) => onChanged(value),
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(color: isSelected ? Colors.white : AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
    );
  }
}

/// Live "Cost Summary Preview" — recomputed on every keystroke; FOB+Freight+Insurance =
/// Estimated CIF mirrors exactly what the backend does with these same three inputs, so
/// this preview never disagrees with the final result once Calculate is pressed.
class _LiveSummaryCard extends StatelessWidget {
  final double fob;
  final double freight;
  final double insurance;
  final double other;
  final String currency;
  const _LiveSummaryCard({required this.fob, required this.freight, required this.insurance, required this.other, required this.currency});

  @override
  Widget build(BuildContext context) {
    final cif = fob + freight + insurance;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withValues(alpha: 0.15))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.preview_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Cost Summary Preview', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              Text(currency, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          _miniRow('FOB', fob),
          _miniRow('Freight', freight),
          _miniRow('Insurance', insurance),
          _miniRow('Other Charges', other),
          const Divider(height: 18),
          _miniRow('Estimated CIF', cif, bold: true),
        ],
      ),
    );
  }

  Widget _miniRow(String label, double value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: bold ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
          Text('₹${value.toStringAsFixed(2)}', style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: bold ? AppColors.primary : AppColors.textPrimary)),
        ],
      ),
    );
  }
}

/// Large gradient CTA with animated loading state.
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

/// The Landed Cost Report — ICEGATE-style worksheet matching the Duty Calculator's report
/// language: green "input" section, then duty rows, then a blue final-cost summary.
class _LandedCostReportCard extends StatelessWidget {
  final String reportNumber;
  final DateTime generatedAt;
  final String hsCode;
  final String productName;
  final LandedCostBreakdown breakdown;
  final DutyBreakdown? dutyDetail;

  const _LandedCostReportCard({
    required this.reportNumber,
    required this.generatedAt,
    required this.hsCode,
    required this.productName,
    required this.breakdown,
    this.dutyDetail,
  });

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    final d = dutyDetail;

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)]), borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: const Text('OBEI', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Landed Cost Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
            _sectionLabel('SHIPMENT DETAILS', AppColors.success),
            const SizedBox(height: 8),
            _greenCell([
              _kv('HS Code', hsCode),
              _kv('Product', productName),
              _kv('FOB Value', '₹${b.fobValue.toStringAsFixed(2)}'),
              _kv('Freight', '₹${b.freight.toStringAsFixed(2)}'),
              _kv('Insurance', '₹${b.insurance.toStringAsFixed(2)}'),
              _kv('Other Charges', '₹${b.otherCharges.toStringAsFixed(2)}'),
              _kv('Assessable Value', '₹${b.cifValue.toStringAsFixed(2)}'),
            ]),
            const SizedBox(height: 20),
            _sectionLabel('DUTY COMPONENTS', AppColors.accent),
            const SizedBox(height: 8),
            if (d != null) ...[
              _orangeRow('Customs Duty (BCD)', d.basicCustomsDuty),
              _orangeRow('SWS', d.socialWelfareSurcharge),
              _orangeRow('IGST', d.igst),
            ] else
              _naRow('BCD / SWS / IGST split', 'Detailed breakdown unavailable — see Total Duty below'),
            _naRow('GST Compensation Cess', 'Not applicable to this HS code'),
            _orangeRow('Total Duty', b.totalDuty, isTotal: true),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Final Landed Cost', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('₹${b.totalLandedCost.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
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
          Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
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

  Widget _orangeRow(String label, double value, {bool isTotal = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: isTotal ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700, fontSize: isTotal ? 14 : 13)),
          Text('₹${value.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: isTotal ? 14.5 : 13.5, color: AppColors.accent)),
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

/// Expandable card used for the three visual-cost-breakdown sections (Cost Components,
/// Duty Components, Final Cost).
class _ExpandableBreakdownCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<(String, double)> rows;
  final bool highlight;
  final String? note;

  const _ExpandableBreakdownCard({required this.title, required this.icon, required this.color, required this.rows, this.highlight = false, this.note});

  @override
  State<_ExpandableBreakdownCard> createState() => _ExpandableBreakdownCardState();
}

class _ExpandableBreakdownCardState extends State<_ExpandableBreakdownCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: widget.highlight ? widget.color.withValues(alpha: 0.06) : null,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(widget.icon, size: 18, color: widget.color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
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
                      children: [
                        if (widget.note != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(widget.note!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
                          ),
                        ...widget.rows.map((r) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(r.$1, style: TextStyle(fontSize: widget.highlight ? 15 : 13, fontWeight: widget.highlight ? FontWeight.w700 : FontWeight.w500)),
                                  Text('₹${r.$2.toStringAsFixed(2)}', style: TextStyle(fontSize: widget.highlight ? 17 : 13.5, fontWeight: FontWeight.w800, color: widget.color)),
                                ],
                              ),
                            )),
                      ],
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

  const _ActionBar({required this.busy, required this.onSaveImage, required this.onDownloadPdf, required this.onShare, required this.onNewCalculation});

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
              _actionButton(Icons.picture_as_pdf_outlined, 'Download PDF', onDownloadPdf, AppColors.error),
              _actionButton(Icons.share_outlined, 'Share Report', onShare, AppColors.accent),
              _actionButton(Icons.refresh, 'New Calculation', onNewCalculation, AppColors.primary),
            ];
            if (isWide) {
              return Row(children: buttons.map((b) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: b))).toList());
            }
            return Wrap(spacing: 8, runSpacing: 8, children: buttons.map((b) => SizedBox(width: (constraints.maxWidth - 8) / 2, child: b)).toList());
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
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), side: BorderSide(color: color.withValues(alpha: 0.4))),
    );
  }
}
