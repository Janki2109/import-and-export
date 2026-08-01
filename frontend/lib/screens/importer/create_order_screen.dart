import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/order_service.dart';

/// Importer fills product + exporter details -> backend creates order + a upi://pay link ->
/// this screen pops back with the result so the dashboard can launch the UPI payment sheet.
class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});
  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _exporterIdCtrl = TextEditingController();
  final _productCtrl = TextEditingController();
  final _hsnCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'units');
  final _priceCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _orderService = OrderService();
  bool _loading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final result = await _orderService.createOrder(
        exporterId: _exporterIdCtrl.text.trim(),
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
                TextFormField(
                  controller: _exporterIdCtrl,
                  decoration: const InputDecoration(labelText: "Exporter's User ID", helperText: 'Get this from the exporter you are dealing with'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
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
