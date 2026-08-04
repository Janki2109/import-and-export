import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/rfq_report_data.dart';
import '../../providers/providers.dart';
import '../../services/rfq_docx.dart';
import '../../services/rfq_report_pdf.dart';
import '../../services/trade_service.dart';

/// Importer posts a Request For Quote — exporters browse open RFQs and respond with
/// quotations. The actual submission still calls the same TradeService.createRFQ() with
/// the same params as before (productName, hsnCode, quantity, unit, targetPrice,
/// destinationCountry, description) — every other field collected here (category,
/// pricing/shipping/additional-requirements sections) is folded into that same
/// `description` string so exporters can see it, without adding any new API field.
class CreateRFQScreen extends ConsumerStatefulWidget {
  /// If set, pre-fills the form from an existing RFQ ("Duplicate" action on My RFQs) —
  /// still results in a brand-new POST /rfqs call once submitted, same as any other RFQ.
  final RfqReportData? duplicateFrom;
  /// Journey 3 — set when reached from a company profile's "Request Quotation" button: the
  /// resulting RFQ is sent only to this exporter instead of the open marketplace broadcast.
  final String? targetExporterId;
  final String? targetCompanyName;
  const CreateRFQScreen({super.key, this.duplicateFrom, this.targetExporterId, this.targetCompanyName});

  @override
  ConsumerState<CreateRFQScreen> createState() => _CreateRFQScreenState();
}

class _CreateRFQScreenState extends ConsumerState<CreateRFQScreen> {
  final _formKey = GlobalKey<FormState>();

  // Section 1 — Product Details
  final _productCtrl = TextEditingController();
  final _hsnCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  // Section 2 — Quantity Details
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'units');
  final _minOrderQtyCtrl = TextEditingController();
  final _packagingTypeCtrl = TextEditingController();

  // Section 3 — Pricing
  final _targetPriceCtrl = TextEditingController();
  String _currency = 'INR';
  String _incoterm = 'FOB';

  // Section 4 — Shipping Details
  final _originCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(); // destination — required, sent to backend
  String _shippingMode = 'air';
  final _deadlineCtrl = TextEditingController();

  // Section 5 — Additional Requirements
  final _qualityCtrl = TextEditingController();
  final _certificationsCtrl = TextEditingController();
  bool _inspectionRequired = false;
  final _packagingInstructionsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final _tradeService = TradeService();
  final _reportKey = GlobalKey();
  bool _loading = false;
  bool _saving = false;

  /// null = still editing form; set once POST /rfqs succeeds, with the real rfq_number
  /// and created_at the backend returned.
  RfqReportData? _postedReport;

  static const _currencies = ['INR', 'USD', 'EUR', 'AED'];
  static const _incoterms = ['EXW', 'FOB', 'CIF', 'CFR', 'DDP', 'DAP'];

  @override
  void initState() {
    super.initState();
    final dup = widget.duplicateFrom;
    if (dup != null) {
      _productCtrl.text = dup.productName;
      _hsnCtrl.text = dup.hsnCode;
      _categoryCtrl.text = dup.category;
      _descriptionCtrl.text = dup.productDescription;
      _qtyCtrl.text = dup.quantity;
      _unitCtrl.text = dup.unit;
      _minOrderQtyCtrl.text = dup.minOrderQty;
      _packagingTypeCtrl.text = dup.packagingType;
      _targetPriceCtrl.text = dup.targetPrice;
      _currency = dup.currency;
      _incoterm = dup.incoterm;
      _originCtrl.text = dup.originCountry;
      _countryCtrl.text = dup.destinationCountry;
      _deadlineCtrl.text = dup.deliveryDeadline;
      _qualityCtrl.text = dup.qualityRequirements;
      _certificationsCtrl.text = dup.certifications;
      _inspectionRequired = dup.inspectionRequired;
      _packagingInstructionsCtrl.text = dup.packagingInstructions;
      _notesCtrl.text = dup.additionalNotes;
    }
  }

  @override
  void dispose() {
    _productCtrl.dispose();
    _hsnCtrl.dispose();
    _categoryCtrl.dispose();
    _descriptionCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _minOrderQtyCtrl.dispose();
    _packagingTypeCtrl.dispose();
    _targetPriceCtrl.dispose();
    _originCtrl.dispose();
    _countryCtrl.dispose();
    _deadlineCtrl.dispose();
    _qualityCtrl.dispose();
    _certificationsCtrl.dispose();
    _packagingInstructionsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _formCompleteness {
    final requiredFilled = [
      _productCtrl.text.trim().isNotEmpty,
      _qtyCtrl.text.trim().isNotEmpty,
      _unitCtrl.text.trim().isNotEmpty,
      _countryCtrl.text.trim().isNotEmpty,
    ].where((v) => v).length;
    return requiredFilled / 4;
  }

  /// Combines every "extra" section into the existing free-text `description` param —
  /// this is the only way these fields reach the exporter, since the backend RFQ model
  /// doesn't have dedicated columns for them. Empty sections are omitted.
  String _buildDescription() {
    final base = _descriptionCtrl.text.trim();
    final extras = <String>[];
    if (_categoryCtrl.text.trim().isNotEmpty) extras.add('Category: ${_categoryCtrl.text.trim()}');
    if (_minOrderQtyCtrl.text.trim().isNotEmpty) extras.add('Min. Order Qty: ${_minOrderQtyCtrl.text.trim()}');
    if (_packagingTypeCtrl.text.trim().isNotEmpty) extras.add('Packaging Type: ${_packagingTypeCtrl.text.trim()}');
    if (_incoterm.isNotEmpty) extras.add('Incoterm: $_incoterm');
    if (_currency != 'INR') extras.add('Currency: $_currency');
    if (_originCtrl.text.trim().isNotEmpty) extras.add('Origin Country: ${_originCtrl.text.trim()}');
    extras.add('Preferred Shipping Mode: ${_shippingMode[0].toUpperCase()}${_shippingMode.substring(1)}');
    if (_deadlineCtrl.text.trim().isNotEmpty) extras.add('Delivery Deadline: ${_deadlineCtrl.text.trim()}');
    if (_qualityCtrl.text.trim().isNotEmpty) extras.add('Quality Requirements: ${_qualityCtrl.text.trim()}');
    if (_certificationsCtrl.text.trim().isNotEmpty) extras.add('Certifications Required: ${_certificationsCtrl.text.trim()}');
    extras.add('Inspection Required: ${_inspectionRequired ? 'Yes' : 'No'}');
    if (_packagingInstructionsCtrl.text.trim().isNotEmpty) extras.add('Packaging Instructions: ${_packagingInstructionsCtrl.text.trim()}');
    if (_notesCtrl.text.trim().isNotEmpty) extras.add('Additional Notes: ${_notesCtrl.text.trim()}');

    final parts = [if (base.isNotEmpty) base, ...extras];
    return parts.join('\n');
  }

  RfqReportData _draftReportData({String rfqNumber = 'Pending', String issueDate = 'Pending — assigned on submit', String status = 'Draft'}) {
    final auth = ref.read(authProvider);
    return RfqReportData(
      rfqNumber: rfqNumber,
      issueDate: issueDate,
      status: status,
      buyerName: auth.currentUser?.fullName ?? '',
      buyerCompany: auth.currentUser?.companyName ?? 'Not specified',
      buyerEmail: auth.currentUser?.email ?? '',
      supplierName: 'To be assigned (open RFQ)',
      productName: _productCtrl.text.trim(),
      hsnCode: _hsnCtrl.text.trim().isEmpty ? 'Not specified' : _hsnCtrl.text.trim(),
      category: _categoryCtrl.text.trim().isEmpty ? 'Not specified' : _categoryCtrl.text.trim(),
      productDescription: _descriptionCtrl.text.trim().isEmpty ? 'Not specified' : _descriptionCtrl.text.trim(),
      quantity: _qtyCtrl.text.trim().isEmpty ? '0' : _qtyCtrl.text.trim(),
      unit: _unitCtrl.text.trim(),
      minOrderQty: _minOrderQtyCtrl.text.trim().isEmpty ? 'Not specified' : _minOrderQtyCtrl.text.trim(),
      packagingType: _packagingTypeCtrl.text.trim().isEmpty ? 'Not specified' : _packagingTypeCtrl.text.trim(),
      targetPrice: _targetPriceCtrl.text.trim().isEmpty ? 'Not specified' : _targetPriceCtrl.text.trim(),
      currency: _currency,
      incoterm: _incoterm,
      originCountry: _originCtrl.text.trim().isEmpty ? 'Not specified' : _originCtrl.text.trim(),
      destinationCountry: _countryCtrl.text.trim(),
      shippingMode: _shippingMode[0].toUpperCase() + _shippingMode.substring(1),
      deliveryDeadline: _deadlineCtrl.text.trim().isEmpty ? 'Not specified' : _deadlineCtrl.text.trim(),
      qualityRequirements: _qualityCtrl.text.trim(),
      certifications: _certificationsCtrl.text.trim(),
      inspectionRequired: _inspectionRequired,
      packagingInstructions: _packagingInstructionsCtrl.text.trim(),
      additionalNotes: _notesCtrl.text.trim(),
    );
  }

  Future<void> _showPreview() async {
    if (!_formKey.currentState!.validate()) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('RFQ Preview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 8),
              _RfqDocumentCard(data: _draftReportData()),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loading
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _submit();
                      },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Confirm & Post RFQ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // The RFQ submission itself is untouched — same TradeService.createRFQ() call with the
  // same params as before.
  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final rfq = await _tradeService.createRFQ(
        productName: _productCtrl.text.trim(),
        hsnCode: _hsnCtrl.text.trim().isEmpty ? null : _hsnCtrl.text.trim(),
        quantity: double.parse(_qtyCtrl.text),
        unit: _unitCtrl.text.trim(),
        targetPrice: _targetPriceCtrl.text.trim().isEmpty ? null : double.tryParse(_targetPriceCtrl.text),
        destinationCountry: _countryCtrl.text.trim(),
        description: _buildDescription().isEmpty ? null : _buildDescription(),
        targetExporterIds: widget.targetExporterId == null ? null : [widget.targetExporterId!],
      );
      if (mounted) {
        setState(() {
          _postedReport = _draftReportData(
            rfqNumber: rfq.rfqNumber,
            issueDate: '${rfq.createdAt.toLocal()}'.split('.').first,
            status: rfq.status.isNotEmpty ? rfq.status[0].toUpperCase() + rfq.status.substring(1) : 'Unknown',
          );
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAsImage() async {
    setState(() => _saving = true);
    try {
      final boundary = _reportKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      await Gal.requestAccess();
      await Gal.putImageBytes(bytes, name: 'rfq-${_postedReport!.rfqNumber}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report Saved Successfully'), backgroundColor: AppColors.success));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save image: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePdf({bool print = false}) async {
    setState(() => _saving = true);
    try {
      final bytes = await buildRfqReportPdf(_postedReport!, title: 'RFQ Report');
      if (print) {
        // Opens the platform print dialog so the user can print (or print-to-PDF) directly.
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'rfq-${_postedReport!.rfqNumber}.pdf');
      } else {
        // Save-only: write the PDF to a temp file and hand it off via the share sheet so the
        // user can save it to their device without going through the print dialog.
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/rfq-${_postedReport!.rfqNumber}.pdf');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(file.path)], text: 'RFQ ${_postedReport!.rfqNumber}');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate PDF: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveDocx() async {
    setState(() => _saving = true);
    try {
      final d = _postedReport!;
      final bytes = buildRfqDocx(
        title: 'RFQ Report',
        companyName: AppConstants.appName,
        rfqNumber: d.rfqNumber,
        issueDate: d.issueDate,
        fields: [
          RfqDocxField('Buyer', '${d.buyerName} (${d.buyerCompany})'),
          RfqDocxField('Supplier', d.supplierName),
          RfqDocxField('Product Name', d.productName),
          RfqDocxField('HS Code', d.hsnCode),
          RfqDocxField('Category', d.category),
          RfqDocxField('Quantity', '${d.quantity} ${d.unit}'),
          RfqDocxField('Target Price', '${d.currency} ${d.targetPrice}'),
          RfqDocxField('Incoterm', d.incoterm),
          RfqDocxField('Origin', d.originCountry),
          RfqDocxField('Destination', d.destinationCountry),
          RfqDocxField('Shipping Mode', d.shippingMode),
          RfqDocxField('Delivery Deadline', d.deliveryDeadline),
          RfqDocxField('Additional Notes', d.additionalNotes.isEmpty ? 'None' : d.additionalNotes),
        ],
        termsAndConditions: RfqReportData.termsAndConditions,
        footer: 'Generated by ${AppConstants.appName}',
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/rfq-${d.rfqNumber}.docx');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'RFQ ${d.rfqNumber}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate DOCX: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    final d = _postedReport!;
    await Share.share('''
RFQ ${d.rfqNumber}
Product: ${d.productName}
Quantity: ${d.quantity} ${d.unit}
Target Price: ${d.currency} ${d.targetPrice}
Destination: ${d.destinationCountry}
Incoterm: ${d.incoterm}

Generated by ${AppConstants.appName}
''');
  }

  Future<void> _email() async {
    final d = _postedReport!;
    final uri = Uri(
      scheme: 'mailto',
      query: 'subject=${Uri.encodeComponent('RFQ ${d.rfqNumber} — ${d.productName}')}'
          '&body=${Uri.encodeComponent('RFQ ${d.rfqNumber}\nProduct: ${d.productName}\nQuantity: ${d.quantity} ${d.unit}\nTarget Price: ${d.currency} ${d.targetPrice}\nDestination: ${d.destinationCountry}')}',
    );
    final ok = await launchUrl(uri);
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No email app found.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_postedReport == null ? 'New RFQ' : 'RFQ Posted'),
        bottom: widget.targetCompanyName == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Sending to ${widget.targetCompanyName}', style: const TextStyle(fontSize: 12)),
                ),
              ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: _postedReport == null ? _buildForm() : _buildPostSubmitReport(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      key: const ValueKey('form'),
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          child: LinearProgressIndicator(value: _formCompleteness, backgroundColor: Colors.grey.shade200, color: AppColors.primary, minHeight: 4),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Form(
              key: _formKey,
              onChanged: () => setState(() {}),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionCard(
                    step: 1,
                    icon: Icons.inventory_2_outlined,
                    title: 'Product Details',
                    children: [
                      TextFormField(controller: _productCtrl, decoration: const InputDecoration(labelText: 'Product Name'), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
                      const SizedBox(height: 12),
                      TextFormField(controller: _hsnCtrl, decoration: const InputDecoration(labelText: 'HS Code (optional)')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _categoryCtrl, decoration: const InputDecoration(labelText: 'Product Category (optional)')),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.add_a_photo_outlined, size: 18), label: const Text('Add Product Image (optional)')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _descriptionCtrl, decoration: const InputDecoration(labelText: 'Product Description (optional)'), maxLines: 3),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    step: 2,
                    icon: Icons.numbers_outlined,
                    title: 'Quantity Details',
                    children: [
                      Row(
                        children: [
                          Expanded(child: TextFormField(controller: _qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity'), validator: (v) {
                            final n = v == null ? null : double.tryParse(v);
                            if (n == null) return 'Invalid';
                            if (n <= 0) return 'Must be greater than 0';
                            return null;
                          })),
                          const SizedBox(width: 10),
                          Expanded(child: TextFormField(controller: _unitCtrl, decoration: const InputDecoration(labelText: 'Unit'), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: _minOrderQtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum Order Quantity (optional)')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _packagingTypeCtrl, decoration: const InputDecoration(labelText: 'Packaging Type (optional)')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    step: 3,
                    icon: Icons.sell_outlined,
                    title: 'Pricing',
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: TextFormField(controller: _targetPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Target Price per Unit (optional)'))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _currency,
                              decoration: const InputDecoration(labelText: 'Currency'),
                              items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                              onChanged: (v) => setState(() => _currency = v ?? 'INR'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _incoterm,
                        decoration: const InputDecoration(labelText: 'Incoterm'),
                        items: _incoterms.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                        onChanged: (v) => setState(() => _incoterm = v ?? 'FOB'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    step: 4,
                    icon: Icons.local_shipping_outlined,
                    title: 'Shipping Details',
                    children: [
                      Row(
                        children: [
                          Expanded(child: TextFormField(controller: _originCtrl, decoration: const InputDecoration(labelText: 'Origin Country (optional)'))),
                          const SizedBox(width: 10),
                          Expanded(child: TextFormField(controller: _countryCtrl, decoration: const InputDecoration(labelText: 'Destination Country'), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Align(alignment: Alignment.centerLeft, child: Text('Preferred Shipping Mode', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _modeChip('Air', 'air', Icons.flight_outlined),
                          _modeChip('Sea', 'sea', Icons.directions_boat_outlined),
                          _modeChip('Road', 'road', Icons.local_shipping_outlined),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: _deadlineCtrl, decoration: const InputDecoration(labelText: 'Delivery Deadline (optional, e.g. 30 days)')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    step: 5,
                    icon: Icons.fact_check_outlined,
                    title: 'Additional Requirements',
                    children: [
                      TextFormField(controller: _qualityCtrl, decoration: const InputDecoration(labelText: 'Quality Requirements (optional)'), maxLines: 2),
                      const SizedBox(height: 12),
                      TextFormField(controller: _certificationsCtrl, decoration: const InputDecoration(labelText: 'Certifications Required (optional)')),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _inspectionRequired,
                        onChanged: (v) => setState(() => _inspectionRequired = v),
                        title: const Text('Inspection Required'),
                      ),
                      TextFormField(controller: _packagingInstructionsCtrl, decoration: const InputDecoration(labelText: 'Packaging Instructions (optional)'), maxLines: 2),
                      const SizedBox(height: 12),
                      TextFormField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Additional Notes (optional)'), maxLines: 3),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _showPreview,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Preview RFQ'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeChip(String label, String value, IconData icon) {
    final selected = _shippingMode == value;
    return ChoiceChip(
      label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: selected ? Colors.white : AppColors.textSecondary), const SizedBox(width: 4), Text(label)]),
      selected: selected,
      onSelected: (_) => setState(() => _shippingMode = value),
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildPostSubmitReport() {
    return Column(
      key: const ValueKey('report'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: _reportKey,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: _RfqDocumentCard(data: _postedReport!),
              ),
            ),
          ),
        ),
        _ActionBar(
          busy: _saving,
          onSaveImage: _saveAsImage,
          onSavePdf: () => _savePdf(),
          onSaveDocx: _saveDocx,
          onPrint: () => _savePdf(print: true),
          onShare: _share,
          onEmail: _email,
          onDone: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// Numbered section card used across the multi-section form — icon + step number act as
/// the "step indicator" the whole form is broken into.
class _SectionCard extends StatelessWidget {
  final int step;
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.step, required this.icon, required this.title, required this.children});

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
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text('$step', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// The professional RFQ document layout — used both for the pre-submit Preview (with
/// "Pending" RFQ number) and the post-submit Report (with the real backend-assigned one).
class _RfqDocumentCard extends StatelessWidget {
  final RfqReportData data;
  const _RfqDocumentCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child)),
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
                      Text('Request For Quotation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      Text(AppConstants.appName, style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('RFQ No.', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                    Text(d.rfqNumber, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(d.issueDate, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(d.status, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _greenSection('BUYER DETAILS', [_kv('Name', d.buyerName), _kv('Company', d.buyerCompany), _kv('Email', d.buyerEmail)])),
                const SizedBox(width: 12),
                Expanded(child: _greenSection('SUPPLIER DETAILS', [_kv('Assigned Supplier', d.supplierName)])),
              ],
            ),
            const SizedBox(height: 12),
            _blueSection('PRODUCT INFORMATION', [
              _kv('Product Name', d.productName),
              _kv('HS Code', d.hsnCode),
              _kv('Category', d.category),
              _kv('Description', d.productDescription),
            ]),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _blueSection('QUANTITY', [_kv('Quantity', '${d.quantity} ${d.unit}'), _kv('Min. Order Qty', d.minOrderQty), _kv('Packaging', d.packagingType)])),
                const SizedBox(width: 12),
                Expanded(child: _blueSection('PRICING', [_kv('Target Price', '${d.currency} ${d.targetPrice}'), _kv('Incoterm', d.incoterm)])),
              ],
            ),
            const SizedBox(height: 12),
            _blueSection('SHIPPING INFORMATION', [
              _kv('Origin', d.originCountry),
              _kv('Destination', d.destinationCountry),
              _kv('Shipping Mode', d.shippingMode),
              _kv('Delivery Deadline', d.deliveryDeadline),
            ]),
            if (d.qualityRequirements.isNotEmpty || d.certifications.isNotEmpty || d.packagingInstructions.isNotEmpty || d.additionalNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              _blueSection('ADDITIONAL REQUIREMENTS', [
                if (d.qualityRequirements.isNotEmpty) _kv('Quality Requirements', d.qualityRequirements),
                if (d.certifications.isNotEmpty) _kv('Certifications', d.certifications),
                _kv('Inspection Required', d.inspectionRequired ? 'Yes' : 'No'),
                if (d.packagingInstructions.isNotEmpty) _kv('Packaging Instructions', d.packagingInstructions),
                if (d.additionalNotes.isNotEmpty) _kv('Notes', d.additionalNotes),
              ]),
            ],
            const SizedBox(height: 16),
            const Text('TERMS & CONDITIONS', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.4)),
            const SizedBox(height: 6),
            const Text(RfqReportData.termsAndConditions, style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.5)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 140, height: 1, color: Colors.grey.shade400),
                    const SizedBox(height: 6),
                    const Text('Authorized Signature', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
                Container(
                  width: 72,
                  height: 52,
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: const Text('Company\nStamp', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Center(child: Text('Generated by ${AppConstants.appName}', style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5))),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5))),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5))),
        ],
      ),
    );
  }

  Widget _greenSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.success.withValues(alpha: 0.25))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(title, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800, fontSize: 11)), const SizedBox(height: 6), ...children],
      ),
    );
  }

  Widget _blueSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withValues(alpha: 0.15))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(title, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 11)), const SizedBox(height: 6), ...children],
      ),
    );
  }
}

/// Bottom export-action row shown after posting — responsive wrap layout.
class _ActionBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onSaveImage;
  final VoidCallback onSavePdf;
  final VoidCallback onSaveDocx;
  final VoidCallback onPrint;
  final VoidCallback onShare;
  final VoidCallback onEmail;
  final VoidCallback onDone;

  const _ActionBar({
    required this.busy,
    required this.onSaveImage,
    required this.onSavePdf,
    required this.onSaveDocx,
    required this.onPrint,
    required this.onShare,
    required this.onEmail,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final buttons = [
                  _btn(Icons.picture_as_pdf_outlined, 'Save PDF', onSavePdf, AppColors.error),
                  _btn(Icons.description_outlined, 'Save DOCX', onSaveDocx, AppColors.heldBlue),
                  _btn(Icons.image_outlined, 'Save Image', onSaveImage, AppColors.secondary),
                  _btn(Icons.print_outlined, 'Print', onPrint, AppColors.accent),
                  _btn(Icons.share_outlined, 'Share', onShare, AppColors.accent),
                  _btn(Icons.email_outlined, 'Email', onEmail, AppColors.primary),
                ];
                return Wrap(spacing: 8, runSpacing: 8, children: buttons.map((b) => SizedBox(width: (constraints.maxWidth - 16) / 3, child: b)).toList());
              },
            ),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: busy ? null : onDone, child: const Text('Done'))),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap, Color color) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onTap,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10), side: BorderSide(color: color.withValues(alpha: 0.4))),
    );
  }
}
