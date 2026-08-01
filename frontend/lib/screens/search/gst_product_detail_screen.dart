import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../models/reference.dart';

/// Product detail page opened from a GST slab's expanded product list — shows the full
/// HS-code record plus a handful of "related products" (same GST slab, different HS code)
/// so the user can keep browsing without going back.
class GSTProductDetailScreen extends StatefulWidget {
  final HSCode product;
  final String categoryName;
  final List<HSCode> relatedProducts;

  const GSTProductDetailScreen({
    super.key,
    required this.product,
    required this.categoryName,
    required this.relatedProducts,
  });

  @override
  State<GSTProductDetailScreen> createState() => _GSTProductDetailScreenState();
}

class _GSTProductDetailScreenState extends State<GSTProductDetailScreen> {
  bool _bookmarked = false;

  @override
  void initState() {
    super.initState();
    _loadBookmark();
  }

  Future<void> _loadBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('gst_bookmarked_hs_codes') ?? [];
    if (mounted) setState(() => _bookmarked = saved.contains(widget.product.code));
  }

  Future<void> _toggleBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('gst_bookmarked_hs_codes') ?? [];
    setState(() => _bookmarked = !_bookmarked);
    if (_bookmarked) {
      saved.add(widget.product.code);
    } else {
      saved.remove(widget.product.code);
    }
    await prefs.setStringList('gst_bookmarked_hs_codes', saved);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_bookmarked ? 'Bookmarked' : 'Removed from bookmarks'), duration: const Duration(seconds: 1)),
      );
    }
  }

  void _copyHsn() {
    Clipboard.setData(ClipboardData(text: widget.product.code));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('HSN code copied'), duration: Duration(seconds: 1)));
  }

  void _share() {
    final p = widget.product;
    Share.share(
      'HSN ${p.code} — ${p.description}\nGST Rate: ${p.igstPercent.toStringAsFixed(0)}%\nCategory: ${widget.categoryName}\nShared from One Bharat Export-Import',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final color = _rateColor(p.igstPercent);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          IconButton(
            icon: Icon(_bookmarked ? Icons.bookmark : Icons.bookmark_border),
            tooltip: 'Bookmark',
            onPressed: _toggleBookmark,
          ),
          IconButton(icon: const Icon(Icons.share_outlined), tooltip: 'Share', onPressed: _share),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.75)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                      child: Text('GST ${p.igstPercent.toStringAsFixed(0)}%',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    const Spacer(),
                    Icon(Icons.inventory_2_outlined, color: Colors.white.withValues(alpha: 0.85)),
                  ],
                ),
                const SizedBox(height: 14),
                Text(p.description, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800), maxLines: 3),
                const SizedBox(height: 6),
                Text(widget.categoryName, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _detailCard(
            icon: Icons.qr_code_2_outlined,
            title: 'HSN Code',
            child: Row(
              children: [
                Expanded(
                  child: Text(p.code, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ),
                OutlinedButton.icon(
                  onPressed: _copyHsn,
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _statTile('GST Rate', '${p.igstPercent.toStringAsFixed(0)}%', Icons.percent, color)),
              const SizedBox(width: 12),
              Expanded(child: _statTile('Customs Duty', '${p.basicCustomsDutyPercent.toStringAsFixed(0)}%', Icons.local_shipping_outlined, AppColors.accent)),
            ],
          ),
          const SizedBox(height: 14),
          _detailCard(
            icon: Icons.category_outlined,
            title: 'Category',
            child: Text(widget.categoryName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 14),
          _detailCard(
            icon: Icons.description_outlined,
            title: 'Description',
            child: Text(
              '${p.description}\n\nHS Chapter ${p.chapter} — classified under India\'s Harmonized System of Nomenclature. Verify with a customs broker before filing, as classification can vary by product variant.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
            ),
          ),
          if (widget.relatedProducts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Related Products', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...widget.relatedProducts.map((r) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Text('${r.igstPercent.toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    title: Text(r.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('HSN ${r.code}', style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => GSTProductDetailScreen(
                          product: r,
                          categoryName: widget.categoryName,
                          relatedProducts: widget.relatedProducts.where((x) => x.code != r.code).toList(),
                        ),
                      ),
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _detailCard({required IconData icon, required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

Color _rateColor(double rate) {
  if (rate <= 0) return AppColors.success;
  if (rate <= 5) return AppColors.heldBlue;
  if (rate <= 12) return AppColors.primary;
  if (rate <= 18) return AppColors.accent;
  return AppColors.error;
}
