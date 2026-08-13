import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/platform.dart';

/// Full read-only detail view for one catalog product — reached by tapping a product in
/// My Catalog. Shows every field the existing Product model/API already returns (the same
/// data ProductCatalogScreen's list already fetched via ProductService.listMine()); no new
/// endpoint, no new fields, no schema change.
class ProductDetailScreen extends StatelessWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (p.imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  p.imageUrl!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 200,
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _section(context, 'Product Details', [
              _row('Product Name', p.name),
              _row('HS Code', p.hsnCode ?? 'Not specified'),
              _row('Description', (p.description == null || p.description!.isEmpty) ? 'Not specified' : p.description!),
            ]),
            _section(context, 'Pricing & Quantity', [
              _row('Unit Price', '₹${p.unitPrice.toStringAsFixed(2)} / ${p.unit}'),
              _row('Minimum Order Quantity', '${p.minOrderQty.toStringAsFixed(0)} ${p.unit}'),
            ]),
            _section(context, 'Status', [
              _row('Listing Status', p.isActive ? 'Active' : 'Inactive'),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12.5)),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}
