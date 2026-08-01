import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../models/negotiation.dart';
import '../../models/trade.dart';
import '../../providers/providers.dart';
import '../../services/chat_service.dart';
import '../../services/negotiation_service.dart';
import '../chat/chat_screen.dart';

const _shippingModes = ['air', 'sea', 'road', 'rail'];
const _incoterms = ['EXW', 'FOB', 'CIF', 'CFR', 'DDP', 'FCA'];
const _paymentTermsOptions = ['100% Advance', '30/70', '50/50', 'Letter of Credit', 'Escrow Milestones'];
const _packagingOptions = ['Standard', 'Custom', 'Branding', 'Pallets', 'Cartons'];

/// Negotiation Engine screen — structured timeline + diff view + counter-offer form.
/// Entirely additive: reads the RFQ/Quotation passed in (already fetched by the caller,
/// no change to those services), and only ever talks to the new /negotiations/* endpoints.
class NegotiationScreen extends ConsumerStatefulWidget {
  final String negotiationId;
  final RFQ rfq;
  const NegotiationScreen({super.key, required this.negotiationId, required this.rfq});

  @override
  ConsumerState<NegotiationScreen> createState() => _NegotiationScreenState();
}

class _NegotiationScreenState extends ConsumerState<NegotiationScreen> {
  final _service = NegotiationService();
  final _chatService = ChatService();
  late Future<(Negotiation, List<NegotiationOffer>)> _future;
  bool _busy = false;
  bool _showCounterForm = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(Negotiation, List<NegotiationOffer>)> _load() async {
    final negotiation = await _service.getById(widget.negotiationId);
    final offers = await _service.getHistory(widget.negotiationId);
    return (negotiation, offers);
  }

  void _refresh() => setState(() {
        _showCounterForm = false;
        _future = _load();
      });

  String get _myRole => ref.read(authProvider).currentUser?.role.name ?? 'importer';

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await _service.acceptOffer(widget.negotiationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer accepted — final quotation locked.'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reject Offer'),
        content: const Text('This will close the negotiation. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _service.rejectOffer(widget.negotiationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer rejected'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitCounterOffer(_CounterOfferInput input) async {
    setState(() => _busy = true);
    try {
      await _service.counterOffer(negotiationId: widget.negotiationId, unitPrice: input.unitPrice, currency: input.currency, quantity: input.quantity, moq: input.moq, deliveryDays: input.deliveryDays, dispatchDays: input.dispatchDays, shippingMode: input.shippingMode, incoterm: input.incoterm, paymentTerms: input.paymentTerms, packaging: input.packaging, validityDate: input.validityDate, specialConditions: input.specialConditions, remarks: input.remarks);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Counter offer sent'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelNegotiation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Negotiation'),
        content: const Text('Are you sure you want to close this negotiation?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Close Negotiation')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _service.closeNegotiation(widget.negotiationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Negotiation closed'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDiscussion(String otherUserId) async {
    try {
      final conversationId = await _chatService.startConversation(otherUserId);
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conversationId, otherUserName: 'Negotiation Discussion')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return AppColors.success;
      case 'rejected':
      case 'expired':
        return AppColors.error;
      case 'closed':
        return AppColors.textSecondary;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Negotiation')),
      body: FutureBuilder<(Negotiation, List<NegotiationOffer>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildSkeleton();
          }
          if (snapshot.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error))));
          }
          final (negotiation, offers) = snapshot.data!;
          final latest = offers.isNotEmpty ? offers.last : null;
          final isOpen = negotiation.status == 'open';
          final myTurn = isOpen && latest != null && latest.createdBy != _myRole;
          final otherUserId = _myRole == 'importer' ? negotiation.exporterId : negotiation.importerId;

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                // Quotation Summary
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(widget.rfq.productName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                            child: Text(negotiation.status.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${widget.rfq.rfqNumber} · Round ${negotiation.currentRound}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
                      const SizedBox(height: 14),
                      // Progress indicator — rounds as dots
                      Row(
                        children: List.generate(offers.length.clamp(1, 6), (i) {
                          return Expanded(
                            child: Container(
                              height: 5,
                              margin: EdgeInsets.only(right: i == offers.length - 1 ? 0 : 4),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4)),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 6),
                      Text('${offers.length} offer${offers.length == 1 ? '' : 's'} exchanged', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _openDiscussion(otherUserId),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Open Discussion'),
                ),
                const SizedBox(height: 20),

                if (latest != null) _currentOfferCard(latest, negotiation),

                const SizedBox(height: 20),
                Text('Negotiation Timeline', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ..._buildTimeline(offers),

                if (isOpen) ...[
                  const SizedBox(height: 20),
                  if (_showCounterForm)
                    _CounterOfferForm(
                      previous: latest,
                      busy: _busy,
                      onCancel: () => setState(() => _showCounterForm = false),
                      onSubmit: _submitCounterOffer,
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (myTurn) ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy ? null : _reject,
                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error), padding: const EdgeInsets.symmetric(vertical: 14)),
                                  icon: const Icon(Icons.close, size: 18),
                                  label: const Text('Reject Offer'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _busy ? null : _accept,
                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 14)),
                                  icon: const Icon(Icons.check, size: 18),
                                  label: const Text('Accept Offer'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => setState(() => _showCounterForm = true),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: const Text('Counter Offer'),
                          ),
                        ] else
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                            child: const Row(children: [
                              Icon(Icons.hourglass_top_outlined, size: 16, color: AppColors.warning),
                              SizedBox(width: 8),
                              Expanded(child: Text('Waiting for the other party to respond.', style: TextStyle(color: AppColors.warning, fontSize: 12.5, fontWeight: FontWeight.w600))),
                            ]),
                          ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _busy ? null : _cancelNegotiation,
                          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: const Text('Cancel Negotiation'),
                        ),
                      ],
                    ),
                ],

                if (negotiation.status == 'accepted') ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.success.withValues(alpha: 0.2))),
                    child: const Row(
                      children: [
                        Icon(Icons.verified, color: AppColors.success),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Agreement reached. Final terms are locked into the quotation — go to My RFQs to accept it and create the order.', style: TextStyle(color: AppColors.success, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _currentOfferCard(NegotiationOffer offer, Negotiation negotiation) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('Current Offer · ${offer.createdBy == 'exporter' ? 'From Exporter' : 'From Importer'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _offerStat('Unit Price', '${offer.currency} ${offer.unitPrice.toStringAsFixed(2)}')),
              Expanded(child: _offerStat('Quantity', offer.quantity.toStringAsFixed(0))),
              Expanded(child: _offerStat('Total', '${offer.currency} ${offer.totalPrice.toStringAsFixed(2)}')),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (offer.deliveryDays != null) _tag('Delivery: ${offer.deliveryDays} days'),
              if (offer.shippingMode != null) _tag('Mode: ${offer.shippingMode}'),
              if (offer.incoterm != null) _tag('Incoterm: ${offer.incoterm}'),
              if (offer.paymentTerms != null) _tag('Payment: ${offer.paymentTerms}'),
              if (offer.packaging != null) _tag('Packaging: ${offer.packaging}'),
              if (offer.moq != null) _tag('MOQ: ${offer.moq}'),
            ],
          ),
          if (offer.remarks != null && offer.remarks!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(offer.remarks!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _offerStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      ],
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }

  List<Widget> _buildTimeline(List<NegotiationOffer> offers) {
    final widgets = <Widget>[];
    for (int i = 0; i < offers.length; i++) {
      final offer = offers[i];
      final previous = i > 0 ? offers[i - 1] : null;
      final changes = previous != null ? _diff(previous, offer) : <String>[];
      final isLast = i == offers.length - 1;
      String label;
      if (i == 0) {
        label = 'Initial Quote';
      } else if (offer.status == 'accepted') {
        label = 'Final Offer — Accepted';
      } else {
        label = 'Counter Offer #$i';
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: _statusColor(offer.status == 'accepted' ? 'accepted' : 'open').withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(offer.status == 'accepted' ? Icons.check : Icons.arrow_forward, size: 15, color: _statusColor(offer.status == 'accepted' ? 'accepted' : 'open')),
                  ),
                  if (!isLast) Expanded(child: Container(width: 2, color: Colors.grey.shade300)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                            Text(offer.createdAt.toLocal().toString().split('.').first, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('By ${offer.createdBy == 'exporter' ? 'Exporter' : 'Importer'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        const SizedBox(height: 8),
                        Text('${offer.currency} ${offer.unitPrice.toStringAsFixed(2)}/unit × ${offer.quantity.toStringAsFixed(0)} = ${offer.currency} ${offer.totalPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        if (changes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: changes.map((c) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                  child: Text(c, style: const TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700)),
                                )).toList(),
                          ),
                        ],
                        if (offer.remarks != null && offer.remarks!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(offer.remarks!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
    }
    return widgets;
  }

  /// Change highlighting — compares this offer to the previous one, field by field.
  List<String> _diff(NegotiationOffer prev, NegotiationOffer next) {
    final changes = <String>[];
    if (prev.unitPrice != next.unitPrice) {
      changes.add(next.unitPrice > prev.unitPrice ? 'Price Increased' : 'Price Decreased');
    }
    if (prev.quantity != next.quantity) {
      changes.add(next.quantity > prev.quantity ? 'Quantity Increased' : 'Quantity Decreased');
    }
    if (prev.deliveryDays != next.deliveryDays) changes.add('Delivery Updated');
    if (prev.dispatchDays != next.dispatchDays) changes.add('Dispatch Updated');
    if (prev.shippingMode != next.shippingMode) changes.add('Shipping Mode Changed');
    if (prev.incoterm != next.incoterm) changes.add('Incoterm Changed');
    if (prev.paymentTerms != next.paymentTerms) changes.add('Payment Terms Changed');
    if (prev.packaging != next.packaging) changes.add('Packaging Changed');
    if (prev.moq != next.moq) changes.add('MOQ Changed');
    if (prev.validityDate != next.validityDate) changes.add('Validity Changed');
    return changes;
  }

  Widget _buildSkeleton() {
    Widget box(double h) => Container(height: h, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(18)));
    return ListView(padding: const EdgeInsets.all(16), children: [box(140), box(80), box(120), box(90), box(90)]);
  }
}

class _CounterOfferInput {
  final double unitPrice;
  final String currency;
  final double quantity;
  final double? moq;
  final int? deliveryDays;
  final int? dispatchDays;
  final String? shippingMode;
  final String? incoterm;
  final String? paymentTerms;
  final String? packaging;
  final DateTime? validityDate;
  final String? specialConditions;
  final String? remarks;

  _CounterOfferInput({
    required this.unitPrice,
    required this.currency,
    required this.quantity,
    this.moq,
    this.deliveryDays,
    this.dispatchDays,
    this.shippingMode,
    this.incoterm,
    this.paymentTerms,
    this.packaging,
    this.validityDate,
    this.specialConditions,
    this.remarks,
  });
}

class _CounterOfferForm extends StatefulWidget {
  final NegotiationOffer? previous;
  final bool busy;
  final VoidCallback onCancel;
  final void Function(_CounterOfferInput) onSubmit;
  const _CounterOfferForm({required this.previous, required this.busy, required this.onCancel, required this.onSubmit});

  @override
  State<_CounterOfferForm> createState() => _CounterOfferFormState();
}

class _CounterOfferFormState extends State<_CounterOfferForm> {
  late final _priceCtrl = TextEditingController(text: widget.previous?.unitPrice.toString());
  late final _qtyCtrl = TextEditingController(text: widget.previous?.quantity.toString());
  late final _moqCtrl = TextEditingController(text: widget.previous?.moq?.toString());
  late final _deliveryCtrl = TextEditingController(text: widget.previous?.deliveryDays?.toString());
  late final _dispatchCtrl = TextEditingController(text: widget.previous?.dispatchDays?.toString());
  final _specialCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  String? _shippingMode;
  String? _incoterm;
  String? _paymentTerms;
  String? _packaging;
  DateTime? _validityDate;

  @override
  void initState() {
    super.initState();
    _shippingMode = widget.previous?.shippingMode;
    _incoterm = widget.previous?.incoterm;
    _paymentTerms = widget.previous?.paymentTerms;
    _packaging = widget.previous?.packaging;
    _validityDate = widget.previous?.validityDate;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Counter Offer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: TextField(controller: _priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unit Price'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _moqCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'MOQ (optional)'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _deliveryCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Delivery (days)'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _dispatchCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dispatch Time (days, optional)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: _shippingMode, decoration: const InputDecoration(labelText: 'Shipping Mode'), items: _shippingModes.map((m) => DropdownMenuItem(value: m, child: Text(m.toUpperCase()))).toList(), onChanged: (v) => setState(() => _shippingMode = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: _incoterm, decoration: const InputDecoration(labelText: 'Incoterm'), items: _incoterms.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(), onChanged: (v) => setState(() => _incoterm = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: _paymentTerms, decoration: const InputDecoration(labelText: 'Payment Terms'), items: _paymentTermsOptions.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(), onChanged: (v) => setState(() => _paymentTerms = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: _packaging, decoration: const InputDecoration(labelText: 'Packaging'), items: _packagingOptions.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(), onChanged: (v) => setState(() => _packaging = v)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Quote Validity'),
            subtitle: Text(_validityDate != null ? _validityDate!.toLocal().toString().split(' ').first : 'Not set'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _validityDate ?? DateTime.now().add(const Duration(days: 15)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (picked != null) setState(() => _validityDate = picked);
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _specialCtrl, decoration: const InputDecoration(labelText: 'Special Conditions (Warranty, Insurance, Certifications...)'), maxLines: 2),
          const SizedBox(height: 12),
          TextField(controller: _remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks'), maxLines: 2),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: widget.busy ? null : widget.onCancel, child: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: widget.busy
                    ? null
                    : () {
                        final price = double.tryParse(_priceCtrl.text);
                        final qty = double.tryParse(_qtyCtrl.text);
                        if (price == null || qty == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price and quantity'), backgroundColor: AppColors.error));
                          return;
                        }
                        widget.onSubmit(_CounterOfferInput(
                          unitPrice: price,
                          currency: 'INR',
                          quantity: qty,
                          moq: double.tryParse(_moqCtrl.text),
                          deliveryDays: int.tryParse(_deliveryCtrl.text),
                          dispatchDays: int.tryParse(_dispatchCtrl.text),
                          shippingMode: _shippingMode,
                          incoterm: _incoterm,
                          paymentTerms: _paymentTerms,
                          packaging: _packaging,
                          validityDate: _validityDate,
                          specialConditions: _specialCtrl.text.trim().isEmpty ? null : _specialCtrl.text.trim(),
                          remarks: _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
                        ));
                      },
                child: widget.busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Send Counter Offer'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
