import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trade.dart';
import '../../services/trade_service.dart';
import 'browse_rfqs_screen.dart';

/// Displayed status for a quotation, derived client-side from status + validityDate
/// (the backend only stores 'sent'/'accepted'/'rejected' — expiry is a UI-side read of
/// validityDate having passed on a still-'sent' quotation).
enum _QuoteState { sent, accepted, rejected, expired }

_QuoteState _stateOf(Quotation q) {
  if (q.status == 'accepted') return _QuoteState.accepted;
  if (q.status == 'rejected') return _QuoteState.rejected;
  if (q.validityDate.isBefore(DateTime.now())) return _QuoteState.expired;
  return _QuoteState.sent;
}

(String, Color, IconData) _stateMeta(_QuoteState s) {
  switch (s) {
    case _QuoteState.sent:
      return ('Sent', AppColors.heldBlue, Icons.send_outlined);
    case _QuoteState.accepted:
      return ('Accepted', AppColors.success, Icons.check_circle_outline);
    case _QuoteState.rejected:
      return ('Rejected', AppColors.error, Icons.cancel_outlined);
    case _QuoteState.expired:
      return ('Expired', AppColors.textSecondary, Icons.schedule_outlined);
  }
}

/// Exporter's own submitted quotations — list view over the existing
/// `GET /quotations/mine` endpoint (no backend change).
class MyQuotationsScreen extends StatefulWidget {
  const MyQuotationsScreen({super.key});
  @override
  State<MyQuotationsScreen> createState() => _MyQuotationsScreenState();
}

class _MyQuotationsScreenState extends State<MyQuotationsScreen> {
  final _tradeService = TradeService();
  late Future<List<Quotation>> _future;
  String _query = '';
  _QuoteState? _filter;

  @override
  void initState() {
    super.initState();
    _future = _tradeService.listMyQuotations();
  }

  void _refresh() => setState(() => _future = _tradeService.listMyQuotations());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Quotations')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Quotation>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            var quotations = snapshot.data ?? [];
            quotations = quotations.where((q) {
              if (_filter != null && _stateOf(q) != _filter) return false;
              if (_query.trim().isNotEmpty && !q.rfqId.toLowerCase().contains(_query.trim().toLowerCase())) return false;
              return true;
            }).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search by RFQ ID',
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
                      _chip('All', _filter == null, () => setState(() => _filter = null)),
                      const SizedBox(width: 6),
                      _chip('Sent', _filter == _QuoteState.sent, () => setState(() => _filter = _QuoteState.sent)),
                      const SizedBox(width: 6),
                      _chip('Accepted', _filter == _QuoteState.accepted, () => setState(() => _filter = _QuoteState.accepted)),
                      const SizedBox(width: 6),
                      _chip('Rejected', _filter == _QuoteState.rejected, () => setState(() => _filter = _QuoteState.rejected)),
                      const SizedBox(width: 6),
                      _chip('Expired', _filter == _QuoteState.expired, () => setState(() => _filter = _QuoteState.expired)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: quotations.isEmpty
                      ? _EmptyState(onBrowse: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BrowseRFQsScreen()));
                          _refresh();
                        })
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: quotations.length,
                          itemBuilder: (context, i) => _QuotationCard(quotation: quotations[i]),
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

class _QuotationCard extends StatelessWidget {
  final Quotation quotation;
  const _QuotationCard({required this.quotation});

  @override
  Widget build(BuildContext context) {
    final state = _stateOf(quotation);
    final (label, color, icon) = _stateMeta(state);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
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
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('RFQ ${quotation.rfqId.substring(0, quotation.rfqId.length > 8 ? 8 : quotation.rfqId.length).toUpperCase()}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        Text('Sent ${quotation.createdAt.toLocal().toString().split(' ').first}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _stat('Quoted Amount', '₹${quotation.totalAmount.toStringAsFixed(2)}')),
                  Expanded(child: _stat('Unit Price', '₹${quotation.unitPrice.toStringAsFixed(2)}')),
                  Expanded(child: _stat('Quantity', '${quotation.quantity}')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showDetails(context),
                      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
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
              const Text('Quotation Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 14),
              _row('RFQ ID', quotation.rfqId),
              _row('Unit Price', '₹${quotation.unitPrice.toStringAsFixed(2)}'),
              _row('Quantity', '${quotation.quantity}'),
              _row('Total Amount', '₹${quotation.totalAmount.toStringAsFixed(2)}'),
              _row('Valid Until', quotation.validityDate.toLocal().toString().split(' ').first),
              if (quotation.terms != null && quotation.terms!.isNotEmpty) _row('Terms', quotation.terms!),
              if (quotation.orderId != null) _row('Order Created', quotation.orderId!),
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
  final VoidCallback onBrowse;
  const _EmptyState({required this.onBrowse});

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
              child: const Icon(Icons.description_outlined, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text('No Quotations Yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            const Text('Quotations you send to importers will show up here.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onBrowse, icon: const Icon(Icons.request_quote_outlined, size: 18), label: const Text('Browse Open RFQs')),
          ],
        ),
      ),
    );
  }
}
