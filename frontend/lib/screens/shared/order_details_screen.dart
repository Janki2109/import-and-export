import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/compliance.dart';
import '../../models/order.dart';
import '../../models/payment_terms.dart';
import '../../models/trade.dart';
import '../../models/user.dart';
import '../../providers/providers.dart';
import '../../services/chat_service.dart';
import '../../services/compliance_service.dart';
import '../../services/order_service.dart';
import '../../services/payment_terms_service.dart';
import '../../services/profile_service.dart';
import '../../services/trade_service.dart';
import '../../services/upload_service.dart';
import '../../widgets/status_badge.dart';
import '../chat/chat_screen.dart';
import 'order_documents_screen.dart';

/// Escrow status derived from the order's own status field — no new endpoint needed, since
/// the order lifecycle (created -> payment_held -> ... -> payment_released/refunded)
/// already encodes exactly this.
String escrowStatusLabel(String orderStatus) {
  switch (orderStatus) {
    case 'created':
      return 'Awaiting Payment';
    case 'payment_held':
    case 'accepted':
    case 'shipped':
    case 'in_transit':
    case 'delivered':
    case 'confirmed':
      return 'Holding Funds';
    case 'payment_released':
      return 'Released';
    case 'refunded':
      return 'Refunded';
    case 'disputed':
      return 'Under Review';
    case 'cancelled':
      return 'Cancelled';
    default:
      return orderStatus;
  }
}

/// Unified Order Details — pulls together data from the order (already fetched by the
/// caller, no new "get order by id" endpoint needed), the shipment, its tracking timeline,
/// and its documents, all via existing endpoints. Purely a read/compose screen: it doesn't
/// duplicate or change any of the existing RFQ/Quotation/Order/Shipment/Wallet logic.
class OrderDetailsScreen extends ConsumerStatefulWidget {
  final Order order;
  const OrderDetailsScreen({super.key, required this.order});

  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  final _orderService = OrderService();
  final _tradeService = TradeService();
  final _profileService = ProfileService();
  final _chatService = ChatService();

  late Future<_OrderDetailsBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_OrderDetailsBundle> _load() async {
    final results = await Future.wait([
      _profileService.getPublicProfile(widget.order.importerId),
      _profileService.getPublicProfile(widget.order.exporterId),
      _orderService.getShipmentByOrder(widget.order.id),
      _tradeService.listDocumentsForOrder(widget.order.id),
      _orderService.getEscrowStatus(widget.order.id),
    ]);
    final shipment = results[2] as Shipment?;
    List<ShipmentEvent> timeline = [];
    PublicUser? logistics;
    if (shipment != null) {
      timeline = await _orderService.getTimeline(shipment.id);
      if (shipment.logisticsId != null) {
        try {
          logistics = await _profileService.getPublicProfile(shipment.logisticsId!);
        } catch (_) {
          // shipment not yet assigned to a resolvable user — timeline still renders fine
        }
      }
    }
    return _OrderDetailsBundle(
      importer: results[0] as PublicUser,
      exporter: results[1] as PublicUser,
      shipment: shipment,
      timeline: timeline,
      documents: results[3] as List<TradeDocument>,
      logistics: logistics,
      escrow: results[4] as EscrowStatusInfo?,
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _chatWith(String otherUserId, String otherUserName) async {
    try {
      final conversationId = await _chatService.startConversation(otherUserId);
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conversationId, otherUserName: otherUserName)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _downloadOrderPdf(_OrderDetailsBundle b) async {
    final o = widget.order;
    final doc = pw.Document();
    const blue = PdfColor.fromInt(0xFF0B3D91);
    const grey = PdfColor.fromInt(0xFF6B7280);
    pw.Widget row(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: grey)),
            pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ]),
        );
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Container(
              width: 40,
              height: 40,
              decoration: pw.BoxDecoration(color: blue, borderRadius: pw.BorderRadius.circular(8)),
              alignment: pw.Alignment.center,
              child: pw.Text('OBEI', style: pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(width: 10),
            pw.Text('Order Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 16),
          pw.Divider(color: PdfColors.grey300),
          row('Order Number', o.orderNumber),
          row('Order Date', '${o.createdAt.day}/${o.createdAt.month}/${o.createdAt.year}'),
          row('Importer', '${b.importer.fullName}${b.importer.companyName != null ? ' (${b.importer.companyName})' : ''}'),
          row('Exporter', '${b.exporter.fullName}${b.exporter.companyName != null ? ' (${b.exporter.companyName})' : ''}'),
          row('Product', o.productName),
          if (o.hsnCode != null) row('HS Code', o.hsnCode!),
          row('Quantity', '${o.quantity} ${o.unit}'),
          row('Unit Price', '₹${o.unitPrice.toStringAsFixed(2)}'),
          row('Total Amount', '₹${o.totalAmount.toStringAsFixed(2)}'),
          row('Order Status', o.status),
          row('Escrow Status', escrowStatusLabel(o.status)),
          if (b.shipment != null) row('Shipment Status', b.shipment!.status),
          if (b.logistics != null) row('Logistics Partner', b.logistics!.companyName ?? b.logistics!.fullName),
          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey300),
          pw.Center(child: pw.Text('Generated by ${AppConstants.appName}', style: const pw.TextStyle(fontSize: 7.5, color: grey))),
        ],
      ),
    ));
    final bytes = await doc.save();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'order-${o.orderNumber}.pdf');
  }

  Future<void> _downloadDocument(String type, String label) async {
    try {
      final doc = await _tradeService.generateDocument(orderId: widget.order.id, type: type);
      // The backend renders and stores the PDF, serving it statically — fetch those bytes
      // and hand them to the print/save dialog, same pattern as every other report screen.
      final response = await Dio().get<List<int>>(
        '${AppConstants.fileHostUrl}${doc.fileUrl}',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(response.data!);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: '$label.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate $label: $e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Scaffold(
      appBar: AppBar(title: Text(o.orderNumber)),
      body: FutureBuilder<_OrderDetailsBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load order details: ${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              ),
            );
          }
          final b = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _SummaryCard(order: o, importer: b.importer, exporter: b.exporter),
                const SizedBox(height: 16),
                _SectionCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Product Details',
                  children: [
                    _kv('Product', o.productName),
                    if (o.hsnCode != null) _kv('HS Code', o.hsnCode!),
                    _kv('Quantity', '${o.quantity} ${o.unit}'),
                    _kv('Unit Price', '₹${o.unitPrice.toStringAsFixed(2)}'),
                    _kv('Total Amount', '₹${o.totalAmount.toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  icon: Icons.payments_outlined,
                  title: 'Payment & Escrow Status',
                  children: [
                    Row(
                      children: [
                        const Expanded(child: Text('Order Status', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
                        StatusBadge(status: o.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _kv('Escrow Status', escrowStatusLabel(o.status)),
                    if (b.escrow?.status == 'held' && b.escrow?.releaseDueAt != null) ...[
                      const SizedBox(height: 10),
                      _AutoReleaseBanner(releaseDueAt: b.escrow!.releaseDueAt!),
                    ],
                    if (ref.read(authProvider).currentUser?.id != o.exporterId) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _chatWith(o.exporterId, b.exporter.fullName),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text('Chat with Exporter'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _PaymentScheduleSectionCard(order: o),
                const SizedBox(height: 16),
                _ComplianceSectionCard(order: o),
                if (b.shipment != null) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    icon: Icons.local_shipping_outlined,
                    title: 'Logistics Partner',
                    children: [
                      _kv('Company', b.logistics?.companyName ?? b.logistics?.fullName ?? 'Assigned — details unavailable'),
                      _kv('Tracking Number', b.shipment!.trackingNumber ?? 'Not set'),
                      _kv('Carrier', b.shipment!.carrierName ?? 'Not set'),
                      Row(
                        children: [
                          const Expanded(child: Text('Shipment Status', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
                          StatusBadge(status: b.shipment!.status),
                        ],
                      ),
                      if (b.logistics != null) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => _chatWith(b.logistics!.id, 'Logistics Partner'),
                          icon: const Icon(Icons.chat_bubble_outline, size: 16),
                          label: const Text('Chat with Logistics'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  _TrackingTimelineCard(timeline: b.timeline, shipment: b.shipment!, order: o),
                ],
                const SizedBox(height: 16),
                _DocumentsSectionCard(
                  orderId: o.id,
                  documents: b.documents,
                  onGenerate: _downloadDocument,
                  onDownloadOrderPdf: () => _downloadOrderPdf(b),
                  onViewAll: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDocumentsScreen(orderId: o.id))).then((_) => _refresh());
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
        ],
      ),
    );
  }
}

class _OrderDetailsBundle {
  final PublicUser importer;
  final PublicUser exporter;
  final Shipment? shipment;
  final List<ShipmentEvent> timeline;
  final List<TradeDocument> documents;
  final PublicUser? logistics;
  final EscrowStatusInfo? escrow;
  _OrderDetailsBundle({required this.importer, required this.exporter, this.shipment, required this.timeline, required this.documents, this.logistics, this.escrow});
}

/// "Awaiting Buyer Confirmation — Auto Release Due In X Days" — shown while escrow is held
/// and hasn't hit its release_due_at yet. Once due (and no dispute raised), the backend cron
/// stops silently auto-releasing and instead notifies admin — so past the due date this
/// banner shows "Under Admin Review" instead of a day count that would otherwise go negative.
class _AutoReleaseBanner extends StatelessWidget {
  final DateTime releaseDueAt;
  const _AutoReleaseBanner({required this.releaseDueAt});

  @override
  Widget build(BuildContext context) {
    final daysLeft = releaseDueAt.difference(DateTime.now()).inDays;
    final overdue = daysLeft < 0 || releaseDueAt.isBefore(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_outlined, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Awaiting Buyer Confirmation', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700, fontSize: 12.5)),
                Text(
                  overdue ? 'Auto Release Under Admin Review' : 'Auto Release Due In $daysLeft Day${daysLeft == 1 ? '' : 's'}',
                  style: TextStyle(color: AppColors.warning.withValues(alpha: 0.85), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Order order;
  final PublicUser importer;
  final PublicUser exporter;
  const _SummaryCard({required this.order, required this.importer, required this.exporter});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.orderNumber, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    Text('${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _party('Importer', importer)),
              const SizedBox(width: 10),
              Expanded(child: _party('Exporter', exporter)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _party(String label, PublicUser user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 10.5)),
          Text(user.fullName, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (user.companyName != null) Text(user.companyName!, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 18, color: AppColors.primary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))]),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Fixed reference sequence for the tracking timeline display, per the requested UX
/// ("Order Confirmed / Payment Completed / Logistics Assigned / Pickup Scheduled / Goods
/// Picked / In Transit / Customs Clearance / Out for Delivery / Delivered"). Ticks reflect
/// steps actually present in the real shipment_events list — nothing here is guessed.
const _timelineSteps = [
  ('assigned', 'Logistics Assigned', Icons.local_shipping_outlined),
  ('pickup_scheduled', 'Pickup Scheduled', Icons.event_available_outlined),
  ('picked_up', 'Goods Picked Up', Icons.inventory_2_outlined),
  ('at_warehouse', 'At Warehouse', Icons.warehouse_outlined),
  ('customs_clearance', 'Customs Clearance', Icons.gavel_outlined),
  ('loaded', 'Loaded on Ship / Flight', Icons.flight_takeoff_outlined),
  ('in_transit', 'In Transit', Icons.route_outlined),
  ('arrived_at_destination', 'Arrived at Destination Port', Icons.anchor_outlined),
  ('out_for_delivery', 'Out for Delivery', Icons.delivery_dining_outlined),
  ('delivered', 'Delivered', Icons.check_circle_outline),
];

/// Order-level lifecycle steps that happen before/after shipment tracking. RFQ/Quotation/
/// Payment/Escrow steps all share `order.createdAt` as their timestamp since the Order model
/// doesn't record the original RFQ/Quotation moments separately (and direct "Buy Now" orders
/// skip RFQ/Quotation entirely, so those ticks just mean "order was placed").
const _preShipmentSteps = [
  ('rfq_created', 'RFQ Created', Icons.description_outlined),
  ('quotation_sent', 'Quotation Sent', Icons.request_quote_outlined),
  ('quotation_accepted', 'Quotation Accepted', Icons.thumb_up_alt_outlined),
  ('payment_received', 'Payment Received', Icons.payments_outlined),
  ('escrow_holding', 'Escrow Holding', Icons.lock_outline),
];

const _postDeliverySteps = [
  ('buyer_confirmation', 'Buyer Confirmation', Icons.verified_user_outlined),
  ('payment_released', 'Payment Released', Icons.account_balance_wallet_outlined),
  ('completed', 'Completed', Icons.task_alt_outlined),
];

class _TrackingTimelineCard extends StatelessWidget {
  final List<ShipmentEvent> timeline;
  final Shipment shipment;
  final Order order;
  const _TrackingTimelineCard({required this.timeline, required this.shipment, required this.order});

  @override
  Widget build(BuildContext context) {
    final reached = timeline.map((e) => e.status).toSet();
    final eventByStatus = {for (final e in timeline) e.status: e};

    // The order existing at all means RFQ/Quotation/Payment/Escrow steps are done (they
    // precede shipment assignment). Delivered shipment status or a later order.status
    // unlocks the trailing buyer-confirmation/payment-released/completed steps.
    final delivered = reached.contains('delivered') || order.status == 'delivered' || order.status == 'buyer_confirmation' || order.status == 'payment_released' || order.status == 'completed';
    final buyerConfirmed = order.status == 'buyer_confirmation' || order.status == 'payment_released' || order.status == 'completed';
    final paymentReleased = order.status == 'payment_released' || order.status == 'completed';
    final completed = order.status == 'completed';

    Widget buildStep(String label, IconData icon, bool done, ShipmentEvent? event, {String? subtitle}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: done ? AppColors.success : Colors.grey.shade200, shape: BoxShape.circle),
              child: Icon(done ? Icons.check : icon, size: 15, color: done ? Colors.white : AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontWeight: done ? FontWeight.w700 : FontWeight.w500, fontSize: 13, color: done ? AppColors.textPrimary : AppColors.textSecondary)),
                  if (event != null)
                    Text(
                      '${event.createdAt.toLocal().toString().split('.').first}${event.location != null ? ' · ${event.location}' : ''}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    )
                  else if (subtitle != null)
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.timeline_outlined, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Order Timeline', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
            const SizedBox(height: 12),
            ..._preShipmentSteps.map((step) => buildStep(
                  step.$2,
                  step.$3,
                  true,
                  null,
                  subtitle: order.createdAt.toLocal().toString().split('.').first,
                )),
            ..._timelineSteps.map((step) {
              final done = reached.contains(step.$1);
              final event = eventByStatus[step.$1];
              return buildStep(step.$2, step.$3, done, event);
            }),
            buildStep(_postDeliverySteps[0].$2, _postDeliverySteps[0].$3, buyerConfirmed, null, subtitle: delivered && !buyerConfirmed ? 'Awaiting buyer confirmation' : null),
            buildStep(_postDeliverySteps[1].$2, _postDeliverySteps[1].$3, paymentReleased, null),
            buildStep(_postDeliverySteps[2].$2, _postDeliverySteps[2].$3, completed, null),
          ],
        ),
      ),
    );
  }
}

class _DocumentsSectionCard extends StatelessWidget {
  final String orderId;
  final List<TradeDocument> documents;
  final Future<void> Function(String type, String label) onGenerate;
  final VoidCallback onDownloadOrderPdf;
  final VoidCallback onViewAll;
  const _DocumentsSectionCard({required this.orderId, required this.documents, required this.onGenerate, required this.onDownloadOrderPdf, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final hasInvoice = documents.any((d) => d.type == 'commercial_invoice');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.folder_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(child: Text('Documents', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              Text('${documents.length} generated', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
            ]),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onGenerate('commercial_invoice', 'Invoice'),
                    icon: const Icon(Icons.receipt_outlined, size: 16),
                    label: Text(hasInvoice ? 'Re-download Invoice' : 'Download Invoice'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDownloadOrderPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Download Order PDF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(onPressed: onViewAll, icon: const Icon(Icons.list_alt_outlined, size: 16), label: const Text('View All Trade Documents')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compliance Center — additive section. Only ever shown here, on an already-created
/// order (the module is inactive before order creation, matching the spec). Fetches and
/// manages its own state independently of the rest of the screen's _OrderDetailsBundle,
/// so it can't affect any existing data flow on this page.
class _ComplianceSectionCard extends ConsumerStatefulWidget {
  final Order order;
  const _ComplianceSectionCard({required this.order});

  @override
  ConsumerState<_ComplianceSectionCard> createState() => _ComplianceSectionCardState();
}

class _ComplianceSectionCardState extends ConsumerState<_ComplianceSectionCard> {
  final _complianceService = ComplianceService();
  final _uploadService = UploadService();
  late Future<OrderComplianceChecklist> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<OrderComplianceChecklist> _load() => _complianceService.getForOrder(widget.order.id);
  void _refresh() => setState(() => _future = _load());

  Future<void> _upload(OrderComplianceItem item) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      final fileUrl = await _uploadService.uploadFile(category: 'compliance', file: File(picked.path), contentType: 'image/jpeg');
      await _complianceService.uploadDocument(complianceId: item.id, fileUrl: fileUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.documentName} uploaded'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showHistory(OrderComplianceItem item) async {
    final history = await _complianceService.getHistory(item.id);
    if (!mounted) return;
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
              Text('${item.documentName} — Version History', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 14),
              if (history.isEmpty)
                const Text('No uploads yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5))
              else
                ...history.map((h) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined, color: AppColors.primary),
                      title: Text(h.createdAt.toLocal().toString().split('.').first, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      subtitle: h.remarks != null ? Text(h.remarks!, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)) : null,
                      trailing: const Icon(Icons.open_in_new, size: 16),
                      onTap: () => launchUrl(Uri.parse(h.fileUrl), mode: LaunchMode.externalApplication),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color) _statusIcon(String status) {
    switch (status) {
      case 'verified':
        return (Icons.verified, AppColors.success);
      case 'uploaded':
        return (Icons.hourglass_top_outlined, AppColors.warning);
      case 'rejected':
        return (Icons.cancel_outlined, AppColors.error);
      default:
        return (Icons.radio_button_unchecked, AppColors.textSecondary);
    }
  }

  Widget _docRow(OrderComplianceItem item, bool isMine) {
    final (icon, color) = _statusIcon(item.status);
    final canUpload = isMine && (item.status == 'pending' || item.status == 'rejected');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: item.status == 'rejected' ? AppColors.error.withValues(alpha: 0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.status == 'rejected' ? AppColors.error.withValues(alpha: 0.2) : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(item.documentName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                        if (item.mandatory)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: const Text('Mandatory', style: TextStyle(fontSize: 9, color: AppColors.error, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    if (item.description != null && item.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(item.description!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ),
                    if (item.status == 'rejected' && item.remarks != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Rejected: ${item.remarks}', style: const TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel(item.status), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (item.uploadedFile != null)
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(item.uploadedFile!), mode: LaunchMode.externalApplication),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 0)),
                  icon: const Icon(Icons.visibility_outlined, size: 14),
                  label: const Text('Preview', style: TextStyle(fontSize: 11.5)),
                ),
              TextButton.icon(
                onPressed: () => _showHistory(item),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 0)),
                icon: const Icon(Icons.history, size: 14),
                label: const Text('History', style: TextStyle(fontSize: 11.5)),
              ),
              if (canUpload)
                TextButton.icon(
                  onPressed: _busy ? null : () => _upload(item),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 0)),
                  icon: const Icon(Icons.upload_outlined, size: 14),
                  label: Text(item.status == 'rejected' ? 'Re-upload' : 'Upload', style: const TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roleGroup(String title, String role, List<OrderComplianceItem> items, String myRole) {
    final roleItems = items.where((i) => i.responsibleRole == role).toList();
    if (roleItems.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...roleItems.map((item) => _docRow(item, role == myRole)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OrderComplianceChecklist>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SectionCard(icon: Icons.verified_user_outlined, title: 'Compliance', children: [
            Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
          ]);
        }
        if (snapshot.hasError) {
          return _SectionCard(icon: Icons.verified_user_outlined, title: 'Compliance', children: [
            Text('Could not load compliance checklist: ${snapshot.error}', style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
          ]);
        }
        final checklist = snapshot.data!;
        if (checklist.items.isEmpty) {
          return _SectionCard(icon: Icons.verified_user_outlined, title: 'Compliance', children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Icon(Icons.fact_check_outlined, size: 34, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                    const SizedBox(height: 10),
                    const Text('No compliance requirements configured for this trade lane yet.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                  ],
                ),
              ),
            ),
          ]);
        }

        final myRole = roleToString(ref.read(authProvider).currentUser?.role ?? UserRole.importer);

        return _SectionCard(
          icon: Icons.verified_user_outlined,
          title: 'Compliance',
          children: [
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: checklist.progressPercent / 100,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(checklist.progressPercent == 100 ? AppColors.success : AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${checklist.progressPercent}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
            if (checklist.shipmentBlocked) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.block, size: 16, color: AppColors.error),
                      SizedBox(width: 6),
                      Text('Shipment Blocked', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ]),
                    const SizedBox(height: 4),
                    Text('Mandatory document missing: ${checklist.missingMandatory.join(', ')}', style: const TextStyle(color: AppColors.error, fontSize: 11)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            _roleGroup('Exporter Documents', 'exporter', checklist.items, myRole),
            _roleGroup('Importer Documents', 'importer', checklist.items, myRole),
            _roleGroup('Logistics Documents', 'logistics', checklist.items, myRole),
          ],
        );
      },
    );
  }
}

const _paymentModelLabels = {
  'advance_100': '100% Advance',
  'advance_balance': 'Advance + Balance',
  'milestone_escrow': 'Milestone Escrow',
  'letter_of_credit': 'Letter of Credit',
  'open_account': 'Open Account',
  'custom': 'Custom Schedule',
};

Color _milestoneStatusColor(String status) {
  switch (status) {
    case 'released':
      return AppColors.success;
    case 'approved':
      return AppColors.heldBlue;
    case 'waiting_approval':
      return AppColors.warning;
    case 'rejected':
      return AppColors.error;
    case 'on_hold':
      return Colors.purple;
    case 'paid':
      return AppColors.primary;
    default:
      return AppColors.textSecondary;
  }
}

String _milestoneStatusLabel(String status) {
  switch (status) {
    case 'waiting_approval':
      return 'Waiting Approval';
    case 'on_hold':
      return 'On Hold';
    default:
      return status[0].toUpperCase() + status.substring(1);
  }
}

/// Payment Schedule — Payment Terms & Milestone Escrow Engine. Additive section appended
/// to Order Details, same pattern as _ComplianceSectionCard above. Shows the negotiated
/// payment model, a milestone timeline, and role-gated actions (importer pays, exporter
/// uploads proof, admin approves/rejects/holds/releases). Money movement always goes
/// through PaymentTermsService, which only ever inserts new ledger_entries rows — the
/// existing single-payment escrow flow for orders without a payment schedule is untouched.
class _PaymentScheduleSectionCard extends ConsumerStatefulWidget {
  final Order order;
  const _PaymentScheduleSectionCard({required this.order});

  @override
  ConsumerState<_PaymentScheduleSectionCard> createState() => _PaymentScheduleSectionCardState();
}

class _PaymentScheduleSectionCardState extends ConsumerState<_PaymentScheduleSectionCard> {
  final _service = PaymentTermsService();
  final _uploadService = UploadService();
  late Future<(PaymentTerms, List<PaymentMilestone>)?> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _service.getByOrder(widget.order.id);
  }

  void _refresh() => setState(() => _future = _service.getByOrder(widget.order.id));

  String get _myRole => roleToString(ref.read(authProvider).currentUser?.role ?? UserRole.importer);
  String get _myId => ref.read(authProvider).currentUser?.id ?? '';

  Future<void> _runAction(Future<void> Function() action, {String? successMessage}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        if (successMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage), backgroundColor: AppColors.success));
        }
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadProof(PaymentMilestone m) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    await _runAction(() async {
      final fileUrl = await _uploadService.uploadFile(category: 'milestone_proof', file: File(picked.path), contentType: 'image/jpeg');
      await _service.uploadProof(m.id, fileUrl);
    }, successMessage: 'Proof uploaded');
  }

  Future<void> _showSetupDialog() async {
    String model = 'advance_100';
    final result = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Set Up Payment Terms', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Choose the payment model agreed during negotiation.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
              const SizedBox(height: 14),
              RadioGroup<String>(
                groupValue: model,
                onChanged: (v) => setSheetState(() => model = v ?? model),
                child: Column(
                  children: _paymentModelLabels.entries
                      .map((e) => RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(e.value, style: const TextStyle(fontSize: 13.5)),
                            value: e.key,
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, model), child: const Text('Continue')),
            ],
          ),
        ),
      ),
    );
    if (result == null) return;

    List<Map<String, dynamic>>? milestones;
    if (result == 'milestone_escrow' || result == 'advance_balance' || result == 'custom') {
      milestones = await _showMilestoneBuilder(result);
      if (milestones == null) return;
    }

    await _runAction(() async {
      await _service.setup(orderId: widget.order.id, paymentModel: result, milestones: milestones);
    }, successMessage: 'Payment schedule created');
  }

  Future<List<Map<String, dynamic>>?> _showMilestoneBuilder(String model) async {
    final rows = <(TextEditingController, TextEditingController)>[
      if (model == 'advance_balance') ...[
        (TextEditingController(text: 'Advance Payment'), TextEditingController(text: '30')),
        (TextEditingController(text: 'Before Shipment'), TextEditingController(text: '70')),
      ] else ...[
        (TextEditingController(text: 'Production Started'), TextEditingController(text: '20')),
        (TextEditingController(text: 'Goods Ready'), TextEditingController(text: '30')),
        (TextEditingController(text: 'Delivery Confirmed'), TextEditingController(text: '50')),
      ],
    ];
    return showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Milestone Schedule', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('Percentages must total 100%.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                const SizedBox(height: 14),
                ...rows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final (titleCtrl, pctCtrl) = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Milestone'))),
                        const SizedBox(width: 8),
                        Expanded(flex: 1, child: TextField(controller: pctCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '%'))),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
                          onPressed: rows.length > 1 ? () => setSheetState(() => rows.removeAt(i)) : null,
                        ),
                      ],
                    ),
                  );
                }),
                OutlinedButton.icon(
                  onPressed: () => setSheetState(() => rows.add((TextEditingController(), TextEditingController(text: '0')))),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Milestone'),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () {
                    final total = rows.fold<double>(0, (sum, r) => sum + (double.tryParse(r.$2.text) ?? 0));
                    if ((total - 100).abs() > 0.1) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Percentages sum to $total%, must be 100%'), backgroundColor: AppColors.error));
                      return;
                    }
                    Navigator.pop(
                        ctx,
                        rows
                            .map((r) => {
                                  'title': r.$1.text.trim().isEmpty ? 'Milestone' : r.$1.text.trim(),
                                  'percentage': double.tryParse(r.$2.text) ?? 0,
                                  'proof_required': true,
                                })
                            .toList());
                  },
                  child: const Text('Create Schedule'),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(PaymentTerms, List<PaymentMilestone>)?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
        }
        final data = snapshot.data;
        if (data == null) {
          final canSetup = widget.order.importerId == _myId || widget.order.exporterId == _myId;
          if (!canSetup) return const SizedBox.shrink();
          return _SectionCard(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Payment Schedule',
            children: [
              const Text('No payment schedule set up for this order yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _busy ? null : _showSetupDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Set Up Payment Terms'),
              ),
            ],
          );
        }

        final (terms, milestones) = data;
        final paidCount = milestones.where((m) => m.status != 'pending').length;
        final releasedAmount = milestones.where((m) => m.status == 'released').fold<double>(0, (s, m) => s + m.amount);
        final remaining = terms.totalAmount - releasedAmount;
        final nextPending = milestones.where((m) => m.status == 'pending').isEmpty ? null : milestones.firstWhere((m) => m.status == 'pending');
        final isImporter = widget.order.importerId == _myId;
        final isExporter = widget.order.exporterId == _myId;
        final isAdmin = _myRole == 'admin';

        return _SectionCard(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Payment Schedule',
          children: [
              Row(
                children: [
                  Expanded(child: Text(_paymentModelLabels[terms.paymentModel] ?? terms.paymentModel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                  Text('${terms.currency} ${terms.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ],
              ),
              if (terms.paymentModel == 'letter_of_credit') ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  _chip('LC No: ${terms.lcNumber ?? '—'}'),
                  _chip('Bank: ${terms.lcBankName ?? '—'}'),
                  _chip('Status: ${terms.lcStatus ?? 'pending'}'),
                ]),
              ],
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: milestones.isEmpty ? 0 : paidCount / milestones.length,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 6),
              Text('Released: ${terms.currency} ${releasedAmount.toStringAsFixed(2)} · Remaining: ${terms.currency} ${remaining.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
              const SizedBox(height: 14),
              ...milestones.map((m) {
                final color = _milestoneStatusColor(m.status);
                final isNext = nextPending?.id == m.id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('${m.releaseOrder}. ${m.title}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                            child: Text(_milestoneStatusLabel(m.status), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${m.percentage.toStringAsFixed(0)}% · ${terms.currency} ${m.amount.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                      if (m.remarks != null && m.remarks!.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text('Remarks: ${m.remarks}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        if (isImporter && isNext && m.status == 'pending')
                          _actionBtn('Pay Next Installment', AppColors.primary, () => _runAction(() => _service.payMilestone(m.id), successMessage: 'Payment recorded')),
                        if (isExporter && m.status == 'paid' && m.proofRequired) _actionBtn('Upload Proof', AppColors.warning, () => _uploadProof(m)),
                        if (isAdmin && m.status == 'waiting_approval') ...[
                          _actionBtn('Approve', AppColors.success, () => _runAction(() => _service.approve(m.id), successMessage: 'Milestone approved')),
                          _actionBtn('Reject', AppColors.error, () => _runAction(() => _service.reject(m.id), successMessage: 'Milestone rejected')),
                          _actionBtn('Hold', Colors.purple, () => _runAction(() => _service.hold(m.id), successMessage: 'Milestone held')),
                        ],
                        if (isAdmin && m.status == 'approved') _actionBtn('Release', AppColors.success, () => _runAction(() => _service.release(m.id), successMessage: 'Funds released')),
                        if (isAdmin && m.status == 'on_hold') _actionBtn('Unhold', Colors.purple, () => _runAction(() => _service.unhold(m.id), successMessage: 'Milestone unheld')),
                      ]),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      );

  Widget _actionBtn(String label, Color color, VoidCallback onTap) => OutlinedButton(
        onPressed: _busy ? null : onTap,
        style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: Text(label, style: const TextStyle(fontSize: 11.5)),
      );
}
