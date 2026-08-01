import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trade.dart';
import '../../services/trade_service.dart';

const _documentTypes = {
  'commercial_invoice': 'Commercial Invoice',
  'packing_list': 'Packing List',
  'certificate_of_origin': 'Certificate of Origin',
  'bill_of_lading': 'Bill of Lading',
  'air_waybill': 'Air Waybill',
  'shipping_invoice': 'Shipping Invoice',
};

/// Generate and view trade documents (Commercial Invoice / Packing List / Certificate of
/// Origin / Bill of Lading / Air Waybill / Shipping Invoice) for a specific order.
/// Available to the importer, exporter, and (for the shipment-related types) the assigned
/// logistics partner.
class OrderDocumentsScreen extends StatefulWidget {
  final String orderId;
  const OrderDocumentsScreen({super.key, required this.orderId});
  @override
  State<OrderDocumentsScreen> createState() => _OrderDocumentsScreenState();
}

class _OrderDocumentsScreenState extends State<OrderDocumentsScreen> {
  final _tradeService = TradeService();
  late Future<List<TradeDocument>> _future;
  String? _generating;

  @override
  void initState() {
    super.initState();
    _future = _tradeService.listDocumentsForOrder(widget.orderId);
  }

  void _refresh() => setState(() => _future = _tradeService.listDocumentsForOrder(widget.orderId));

  Future<void> _generate(String type) async {
    setState(() => _generating = type);
    try {
      await _tradeService.generateDocument(orderId: widget.orderId, type: type);
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _generating = null);
    }
  }

  Future<void> _open(TradeDocument doc) async {
    final uri = Uri.parse('${AppConstants.fileHostUrl}${doc.fileUrl}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open document')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trade Documents')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<TradeDocument>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final generated = {for (final d in snapshot.data ?? <TradeDocument>[]) d.type: d};
            return ListView(
              padding: const EdgeInsets.all(16),
              children: _documentTypes.entries.map((entry) {
                final doc = generated[entry.key];
                final isGenerating = _generating == entry.key;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.primary),
                    title: Text(entry.value),
                    subtitle: Text(doc != null
                        ? 'Generated on ${doc.createdAt.toLocal().toString().split(' ').first}'
                        : 'Not generated yet'),
                    trailing: isGenerating
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : doc != null
                            ? OutlinedButton(onPressed: () => _open(doc), child: const Text('View'))
                            : ElevatedButton(onPressed: () => _generate(entry.key), child: const Text('Generate')),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
