import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
  'export_declaration': 'Export Declaration',
  'import_declaration': 'Import Declaration',
  'inspection_certificate': 'Inspection Certificate',
  'insurance_certificate': 'Insurance Certificate',
};

/// Generate and view trade documents (all 10 Journey 9 document types) for a specific order.
/// Available to the importer, exporter, and (for the shipment-related types) the assigned
/// logistics partner. Documents are stored encrypted, digitally signed (HMAC-SHA256), and
/// shared only via short-lived signed download links — never a permanent public URL.
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
    // BUG FIX (Journey 9): doc.fileUrl is now a complete, short-lived signed URL built by the
    // backend (scheme+host+path+query) — it previously was a bare path meant to be appended to
    // fileHostUrl. Prepending fileHostUrl now would corrupt the URL.
    final uri = Uri.parse(doc.fileUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open document')));
    }
  }

  Future<void> _showHistory(TradeDocument doc) async {
    try {
      final versions = await _tradeService.listDocumentVersions(doc.id);
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Version History', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 12),
              if (versions.isEmpty) const Text('No versions found.', style: TextStyle(color: AppColors.textSecondary)),
              ...versions.map((v) => ListTile(
                    leading: CircleAvatar(child: Text('v${v.version}')),
                    title: Text(v.createdAt.toLocal().toString().split('.').first),
                    subtitle: Text('SHA-256: ${v.checksum.substring(0, 16)}…', style: const TextStyle(fontSize: 11)),
                    trailing: TextButton(
                      onPressed: () => launchUrl(Uri.parse(v.fileUrl), mode: LaunchMode.externalApplication),
                      child: const Text('Open'),
                    ),
                  )),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
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
                        ? 'v${doc.version} · Generated on ${doc.createdAt.toLocal().toString().split(' ').first}'
                        : 'Not generated yet'),
                    trailing: isGenerating
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : doc != null
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (doc.version > 1)
                                    IconButton(
                                      icon: const Icon(Icons.history, size: 20),
                                      tooltip: 'Version History',
                                      onPressed: () => _showHistory(doc),
                                    ),
                                  OutlinedButton(onPressed: () => _open(doc), child: const Text('View')),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.refresh, size: 20),
                                    tooltip: 'Regenerate',
                                    onPressed: () => _generate(entry.key),
                                  ),
                                ],
                              )
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
