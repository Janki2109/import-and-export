import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/platform.dart';
import '../../services/platform_service.dart';

/// Importer browses the exporter product catalog (separate from RFQ — this is a
/// browse-and-discover view of standing product listings, not a negotiated request).
class BrowseCatalogScreen extends StatefulWidget {
  const BrowseCatalogScreen({super.key});
  @override
  State<BrowseCatalogScreen> createState() => _BrowseCatalogScreenState();
}

class _BrowseCatalogScreenState extends State<BrowseCatalogScreen> {
  final _productService = ProductService();
  final _controller = TextEditingController();
  List<Product> _results = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await _productService.search(query);
      if (mounted) setState(() => _results = results);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Product Catalog')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Search products',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('No products found.', style: TextStyle(color: AppColors.textSecondary)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final p = _results[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(p.name),
                          subtitle: Text([
                            '₹${p.unitPrice.toStringAsFixed(2)}/${p.unit}',
                            'MOQ ${p.minOrderQty.toStringAsFixed(0)}',
                            if (p.hsnCode != null) 'HS ${p.hsnCode}',
                          ].join(' · ')),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
