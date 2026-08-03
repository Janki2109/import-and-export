import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/company.dart';
import '../../services/order_service.dart';
import 'browse_exporters_screen.dart';

/// Importer fills product + exporter details -> backend creates order + a upi://pay link ->
/// this screen pops back with the result so the dashboard can launch the UPI payment sheet.
///
/// BUG FIX (Journey 3): exporterId/exporterName previously had to be typed/pasted in as a raw
/// user ID the importer had to obtain out-of-band. Now optionally pre-filled when reached from
/// a company profile (CompanyProfileScreen), or picked from the supplier directory here.
class CreateOrderScreen extends StatefulWidget {
  final String? exporterId;
  final String? exporterName;
  const CreateOrderScreen({super.key, this.exporterId, this.exporterName});
  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _exporterId;
  String? _exporterName;
  final _productCtrl = TextEditingController();
  final _hsnCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'units');
  final _priceCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _orderService = OrderService();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _exporterId = widget.exporterId;
    _exporterName = widget.exporterName;
  }

  Future<void> _pickExporter() async {
    final picked = await Navigator.of(context).push<DirectoryListing>(
      MaterialPageRoute(builder: (_) => const BrowseExportersScreen(picking: true)),
    );
    if (picked != null) {
      setState(() {
        _exporterId = picked.userId;
        _exporterName = picked.companyName;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_exporterId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a supplier first.'), backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await _orderService.createOrder(
        exporterId: _exporterId!,
        productName: _productCtrl.text.trim(),
        hsnCode: _hsnCtrl.text.trim().isEmpty ? null : _hsnCtrl.text.trim(),
        quantity: double.parse(_qtyCtrl.text),
        unit: _unitCtrl.text.trim(),
        unitPrice: double.parse(_priceCtrl.text),
        deliveryAddress: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final total = qty * price;

    return Scaffold(
      appBar: AppBar(title: const Text('New Order')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: _pickExporter,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Supplier',
                      suffixIcon: Icon(Icons.search),
                    ),
                    child: Text(
                      _exporterName ?? 'Tap to choose a supplier',
                      style: TextStyle(color: _exporterName == null ? AppColors.textSecondary : null),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _productCtrl,
                  decoration: const InputDecoration(labelText: 'Product Name'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _hsnCtrl,
                  decoration: const InputDecoration(labelText: 'HSN Code (optional)'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Quantity'),
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _unitCtrl,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Unit Price (₹)'),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Delivery Address (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                if (total > 0)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total (held in escrow):', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('₹${total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.primary)),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create Order & Pay'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
