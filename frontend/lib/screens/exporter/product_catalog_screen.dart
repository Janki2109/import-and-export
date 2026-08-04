import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/platform.dart';
import '../../services/platform_service.dart';

class ProductCatalogScreen extends StatefulWidget {
  const ProductCatalogScreen({super.key});
  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  final _productService = ProductService();
  late Future<List<Product>> _future;

  @override
  void initState() {
    super.initState();
    _future = _productService.listMine();
  }

  void _refresh() => setState(() => _future = _productService.listMine());

  Future<void> _addProduct() async {
    final nameCtrl = TextEditingController();
    final hsnCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'units');
    final priceCtrl = TextEditingController();
    final moqCtrl = TextEditingController(text: '1');
    String? errorText;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Add Product', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Product Name')),
                const SizedBox(height: 12),
                TextField(controller: hsnCtrl, decoration: const InputDecoration(labelText: 'HS Code (optional)')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unit Price (₹)'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Unit'))),
                ]),
                const SizedBox(height: 12),
                TextField(controller: moqCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum Order Quantity')),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(errorText!, style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final price = double.tryParse(priceCtrl.text.trim());
                    if (name.isEmpty) {
                      setSheetState(() => errorText = 'Product name is required.');
                      return;
                    }
                    if (price == null || price <= 0) {
                      setSheetState(() => errorText = 'Enter a valid unit price greater than 0.');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Add Product'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
    if (confirmed != true) return;

    try {
      await _productService.create(
        name: nameCtrl.text.trim(),
        hsnCode: hsnCtrl.text.trim().isEmpty ? null : hsnCtrl.text.trim(),
        unit: unitCtrl.text.trim(),
        unitPrice: double.parse(priceCtrl.text.trim()),
        minOrderQty: double.tryParse(moqCtrl.text) ?? 1,
      );
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Catalog')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addProduct, icon: const Icon(Icons.add), label: const Text('Add Product')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Product>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final products = snapshot.data ?? [];
            if (products.isEmpty) {
              return const Center(child: Text('No products listed yet.', style: TextStyle(color: AppColors.textSecondary)));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: products.length,
              itemBuilder: (context, i) {
                final p = products[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(p.name),
                    subtitle: Text('₹${p.unitPrice.toStringAsFixed(2)}/${p.unit} · MOQ ${p.minOrderQty.toStringAsFixed(0)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () async {
                        await _productService.delete(p.id);
                        if (mounted) _refresh();
                      },
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
