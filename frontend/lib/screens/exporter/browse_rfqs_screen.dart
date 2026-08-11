import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trade.dart';
import '../../services/trade_service.dart';

enum _SortOrder { newest, oldest }

/// Exporter browses open RFQs from importers and submits a quotation against one.
class BrowseRFQsScreen extends StatefulWidget {
  const BrowseRFQsScreen({super.key});
  @override
  State<BrowseRFQsScreen> createState() => _BrowseRFQsScreenState();
}

class _BrowseRFQsScreenState extends State<BrowseRFQsScreen> {
  final _tradeService = TradeService();
  late Future<List<RFQ>> _future;

  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _countryFilter;
  _SortOrder _sort = _SortOrder.newest;

  @override
  void initState() {
    super.initState();
    _future = _tradeService.listOpenRFQs();
  }

  void _refresh() => setState(() => _future = _tradeService.listOpenRFQs());

  List<RFQ> _applyFilters(List<RFQ> rfqs) {
    var list = rfqs.where((r) {
      if (_query.trim().isNotEmpty) {
        final q = _query.trim().toLowerCase();
        if (!r.productName.toLowerCase().contains(q) && !(r.hsnCode ?? '').toLowerCase().contains(q)) return false;
      }
      if (_countryFilter != null && r.destinationCountry != _countryFilter) return false;
      return true;
    }).toList();
    list.sort((a, b) => _sort == _SortOrder.newest ? b.createdAt.compareTo(a.createdAt) : a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Open RFQs')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<RFQ>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final all = snapshot.data ?? [];
            final rfqs = _applyFilters(all);
            final countries = all.map((r) => r.destinationCountry).toSet().toList()..sort();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search by product or HS code',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Theme.of(context).cardTheme.color,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _chip('All Countries', _countryFilter == null, () => setState(() => _countryFilter = null)),
                      const SizedBox(width: 6),
                      ...countries.map((c) => Padding(padding: const EdgeInsets.only(right: 6), child: _chip(c, _countryFilter == c, () => setState(() => _countryFilter = _countryFilter == c ? null : c)))),
                      const SizedBox(width: 10),
                      Container(width: 1, height: 24, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 4)),
                      const SizedBox(width: 4),
                      _chip('Newest', _sort == _SortOrder.newest, () => setState(() => _sort = _SortOrder.newest)),
                      const SizedBox(width: 6),
                      _chip('Oldest', _sort == _SortOrder.oldest, () => setState(() => _sort = _SortOrder.oldest)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: rfqs.isEmpty
                      ? _EmptyState(onRefresh: _refresh)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: rfqs.length,
                          itemBuilder: (context, i) => _RFQCard(
                            rfq: rfqs[i],
                            index: i,
                            onQuote: () async {
                              final submitted = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(builder: (_) => SubmitQuotationScreen(rfq: rfqs[i])),
                              );
                              if (submitted == true && mounted) _refresh();
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
    );
  }
}

class _RFQCard extends StatelessWidget {
  final RFQ rfq;
  final int index;
  final VoidCallback onQuote;
  const _RFQCard({required this.rfq, required this.index, required this.onQuote});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (index * 25).clamp(0, 250)),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: child)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showDetails(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                        child: rfq.productImageUrl != null
                            ? Image.network(
                                rfq.productImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 24),
                              )
                            : const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rfq.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(rfq.rfqNumber, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                              if (rfq.hsnCode != null && rfq.hsnCode!.isNotEmpty) ...[
                                const Text(' · ', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                Text('HS ${rfq.hsnCode}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: const Text('Open', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 10.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _tag(Icons.public_outlined, rfq.destinationCountry),
                    _tag(Icons.scale_outlined, '${rfq.quantity} ${rfq.unit}'),
                    if (rfq.targetPrice != null) _tag(Icons.sell_outlined, 'Target ₹${rfq.targetPrice!.toStringAsFixed(2)}/unit'),
                    _tag(Icons.schedule_outlined, _relativeTime(rfq.createdAt)),
                  ],
                ),
                if (rfq.description != null && rfq.description!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(rfq.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showDetails(context),
                        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        label: const Text('View Details'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onQuote,
                        style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        icon: const Icon(Icons.request_quote_outlined, size: 16),
                        label: const Text('Send Quote'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rfq.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 14),
              if (rfq.productImageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    rfq.productImageUrl!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _row('RFQ Number', rfq.rfqNumber),
              if (rfq.hsnCode != null) _row('HS Code', rfq.hsnCode!),
              _row('Quantity', '${rfq.quantity} ${rfq.unit}'),
              _row('Destination', rfq.destinationCountry),
              if (rfq.targetPrice != null) _row('Target Price', '₹${rfq.targetPrice!.toStringAsFixed(2)}/unit'),
              _row('Posted', rfq.createdAt.toLocal().toString().split(' ').first),
              if (rfq.description != null && rfq.description!.isNotEmpty) _row('Description', rfq.description!),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onQuote();
                  },
                  icon: const Icon(Icons.request_quote_outlined, size: 18),
                  label: const Text('Send Quote'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.12), AppColors.primary.withValues(alpha: 0.04)]), shape: BoxShape.circle),
              child: const Icon(Icons.request_quote_outlined, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text('No RFQs Available', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            const Text('New buying requests from importers will appear here.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh')),
          ],
        ),
      ),
    );
  }
}

class SubmitQuotationScreen extends StatefulWidget {
  final RFQ rfq;
  const SubmitQuotationScreen({super.key, required this.rfq});
  @override
  State<SubmitQuotationScreen> createState() => _SubmitQuotationScreenState();
}

class _SubmitQuotationScreenState extends State<SubmitQuotationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _priceCtrl = TextEditingController();
  late final _qtyCtrl = TextEditingController(text: widget.rfq.quantity.toString());
  final _termsCtrl = TextEditingController();
  DateTime _validityDate = DateTime.now().add(const Duration(days: 15));
  final _tradeService = TradeService();
  bool _loading = false;

  double get _unitPrice => double.tryParse(_priceCtrl.text) ?? 0;
  double get _quantity => double.tryParse(_qtyCtrl.text) ?? 0;
  double get _total => _unitPrice * _quantity;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _tradeService.submitQuotation(
        rfqId: widget.rfq.id,
        unitPrice: _unitPrice,
        quantity: _quantity,
        validityDate: _validityDate,
        terms: _termsCtrl.text.trim().isEmpty ? null : _termsCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quotation sent successfully.'), backgroundColor: AppColors.success));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPreview() {
    if (!_formKey.currentState!.validate()) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Quotation Preview', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 14),
              _row('Product', widget.rfq.productName),
              _row('Unit Price', '₹${_unitPrice.toStringAsFixed(2)}'),
              _row('Quantity', '$_quantity ${widget.rfq.unit}'),
              _row('Total Amount', '₹${_total.toStringAsFixed(2)}'),
              _row('Valid Until', _validityDate.toLocal().toString().split(' ').first),
              if (_termsCtrl.text.trim().isNotEmpty) _row('Terms', _termsCtrl.text.trim()),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _submit();
                        },
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Confirm & Send'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Quote: ${widget.rfq.productName}')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: _formKey,
            onChanged: () => setState(() {}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionCard(
                  title: 'Product Details',
                  icon: Icons.inventory_2_outlined,
                  children: [
                    _kv('Product', widget.rfq.productName),
                    _kv('RFQ Number', widget.rfq.rfqNumber),
                    _kv('Destination', widget.rfq.destinationCountry),
                    if (widget.rfq.targetPrice != null) _kv('Target Price', '₹${widget.rfq.targetPrice!.toStringAsFixed(2)}/unit'),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Pricing',
                  icon: Icons.sell_outlined,
                  children: [
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Unit Price (₹)'),
                      validator: (v) {
                        final n = v == null ? null : double.tryParse(v);
                        if (n == null) return 'Invalid';
                        if (n <= 0) return 'Must be greater than 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Quantity (${widget.rfq.unit})'),
                      validator: (v) {
                        final n = v == null ? null : double.tryParse(v);
                        if (n == null) return 'Invalid';
                        if (n <= 0) return 'Must be greater than 0';
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Shipping & Delivery',
                  icon: Icons.local_shipping_outlined,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Valid Until'),
                      subtitle: Text(_validityDate.toLocal().toString().split(' ').first),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _validityDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => _validityDate = picked);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Remarks',
                  icon: Icons.notes_outlined,
                  children: [
                    TextFormField(
                      controller: _termsCtrl,
                      decoration: const InputDecoration(labelText: 'Terms (optional)'),
                      maxLines: 3,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.summarize_outlined, size: 16, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text('Summary', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ]),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Quote Amount', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                          Text('₹${_total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _showPreview,
                        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('Preview Quote'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: _loading
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_outlined, size: 18),
                        label: const Text('Send Quote'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          ]),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
