import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reference.dart';
import '../../services/search_service.dart';
import 'gst_product_detail_screen.dart';

/// One GST slab (e.g. "18% — Standard goods") together with every HS-code product that
/// falls under it — computed client-side by grouping the HS-code list by igst_percent
/// against the official rate_percent categories, using only the existing
/// /search/gst-rates and /search/hs-codes endpoints (no backend changes).
class _GSTSlab {
  final GSTRate rate;
  final List<HSCode> products;
  _GSTSlab({required this.rate, required this.products});
}

class GSTRatesScreen extends StatefulWidget {
  const GSTRatesScreen({super.key});
  @override
  State<GSTRatesScreen> createState() => _GSTRatesScreenState();
}

class _GSTRatesScreenState extends State<GSTRatesScreen> {
  final _searchService = SearchService();
  final _searchCtrl = TextEditingController();

  late Future<List<_GSTSlab>> _future;
  final Set<double> _expanded = {};
  String _activeFilter = 'All';
  String _query = '';
  DateTime? _loadedAt;

  static const _filters = ['All', '0%', '5%', '12%', '18%', '28%'];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<_GSTSlab>> _load() async {
    final results = await Future.wait([
      _searchService.listGSTRates(),
      _searchService.searchHSCodes(''),
    ]);
    final rates = results[0] as List<GSTRate>;
    final hsCodes = results[1] as List<HSCode>;
    _loadedAt = DateTime.now();

    return rates.map((r) {
      final products = hsCodes.where((h) => (h.igstPercent - r.ratePercent).abs() < 0.01).toList()
        ..sort((a, b) => a.description.compareTo(b.description));
      return _GSTSlab(rate: r, products: products);
    }).toList()
      ..sort((a, b) => a.rate.ratePercent.compareTo(b.rate.ratePercent));
  }

  List<_GSTSlab> _applyFilters(List<_GSTSlab> slabs) {
    var filtered = slabs;
    if (_activeFilter != 'All') {
      final wantRate = double.parse(_activeFilter.replaceAll('%', ''));
      filtered = filtered.where((s) => (s.rate.ratePercent - wantRate).abs() < 0.01).toList();
    }
    if (_query.trim().isEmpty) return filtered;

    final q = _query.trim().toLowerCase();
    return filtered
        .map((s) => _GSTSlab(
              rate: s.rate,
              products: s.products.where((p) => p.description.toLowerCase().contains(q) || p.code.toLowerCase().contains(q)).toList(),
            ))
        .where((s) => s.products.isNotEmpty || s.rate.category.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GST Rate Slabs')),
      body: FutureBuilder<List<_GSTSlab>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load GST rates: ${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              ),
            );
          }
          final allSlabs = snapshot.data ?? [];
          final totalProducts = allSlabs.fold<int>(0, (sum, s) => sum + s.products.length);
          final slabs = _applyFilters(allSlabs);
          final isSearching = _query.trim().isNotEmpty;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _HeaderCard(slabCount: allSlabs.length, productCount: totalProducts)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search by product name or HSN code',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final f = _filters[i];
                      final selected = _activeFilter == f;
                      return ChoiceChip(
                        label: Text(f),
                        selected: selected,
                        onSelected: (_) => setState(() => _activeFilter = f),
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
                      );
                    },
                  ),
                ),
              ),
              if (slabs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off, size: 48, color: AppColors.textSecondary),
                          const SizedBox(height: 12),
                          Text('No matches for "$_query"', style: const TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  sliver: SliverList.builder(
                    itemCount: slabs.length,
                    itemBuilder: (context, i) {
                      final slab = slabs[i];
                      final expanded = isSearching || _expanded.contains(slab.rate.ratePercent);
                      return _SlabCard(
                        slab: slab,
                        expanded: expanded,
                        forceExpanded: isSearching,
                        onToggle: () => setState(() {
                          if (_expanded.contains(slab.rate.ratePercent)) {
                            _expanded.remove(slab.rate.ratePercent);
                          } else {
                            _expanded.add(slab.rate.ratePercent);
                          }
                        }),
                        onProductTap: (product) => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GSTProductDetailScreen(
                              product: product,
                              categoryName: slab.rate.category,
                              relatedProducts: slab.products.where((p) => p.code != product.code).take(5).toList(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Center(
                    child: Text(
                      _loadedAt != null ? 'Last updated: ${_formatTime(_loadedAt!)}' : '',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${t.day}/${t.month}/${t.year} at $h:$m';
  }
}

/// Premium gradient header summarizing the GST slab catalog at a glance.
class _HeaderCard extends StatelessWidget {
  final int slabCount;
  final int productCount;
  const _HeaderCard({required this.slabCount, required this.productCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
                child: const Icon(Icons.receipt_long_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('India GST Rate Slabs', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Standard GST slabs applicable across HSN-classified goods, from essential items to luxury goods.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statChip(Icons.layers_outlined, '$slabCount', 'Slabs'),
              const SizedBox(width: 10),
              _statChip(Icons.inventory_2_outlined, '$productCount', 'Products indexed'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expandable slab card — collapsed shows rate badge, category, product count; expanded
/// reveals the complete product list with a smooth [AnimatedSize] transition.
class _SlabCard extends StatelessWidget {
  final _GSTSlab slab;
  final bool expanded;
  final bool forceExpanded;
  final VoidCallback onToggle;
  final void Function(HSCode) onProductTap;

  const _SlabCard({
    required this.slab,
    required this.expanded,
    required this.forceExpanded,
    required this.onToggle,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _rateColor(slab.rate.ratePercent);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: forceExpanded ? null : onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Center(
                      child: Text('${slab.rate.ratePercent.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(slab.rate.category, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 3),
                        if (slab.rate.description != null)
                          Text(slab.rate.description!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                          child: Text('${slab.products.length} product${slab.products.length == 1 ? '' : 's'}',
                              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  if (!forceExpanded)
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
                ? Column(
                    children: [
                      Divider(height: 1, color: Colors.grey.shade200),
                      if (slab.products.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No indexed products under this slab yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                        )
                      else
                        ...slab.products.map((p) => _ProductRow(product: p, color: color, onTap: () => onProductTap(p))),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final HSCode product;
  final Color color;
  final VoidCallback onTap;
  const _ProductRow({required this.product, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
              child: Text(product.code, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(product.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
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
