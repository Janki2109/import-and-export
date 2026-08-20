import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/negotiation.dart';
import '../../services/negotiation_service.dart';
import '../../widgets/admin_ui_kit.dart';

const _statusFilters = [null, 'open', 'accepted', 'rejected', 'expired', 'closed'];
const _statusLabels = {null: 'All', 'open': 'Open', 'accepted': 'Accepted', 'rejected': 'Rejected', 'expired': 'Expired', 'closed': 'Closed'};

/// Admin Negotiation Center — additive admin module. View negotiations across the
/// platform, search/filter, view offer history, and force-close a stuck negotiation.
/// Admin never edits negotiated values directly — only the parties do that.
class AdminNegotiationScreen extends StatefulWidget {
  const AdminNegotiationScreen({super.key});
  @override
  State<AdminNegotiationScreen> createState() => _AdminNegotiationScreenState();
}

class _AdminNegotiationScreenState extends State<AdminNegotiationScreen> {
  final _service = NegotiationService();
  late Future<List<AdminNegotiationRow>> _future;
  String? _statusFilter;
  String _query = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _service.adminList();
  }

  void _refresh() => setState(() => _future = _service.adminList(status: _statusFilter));

  Future<void> _forceClose(AdminNegotiationRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Force Close Negotiation'),
        content: Text('Close this negotiation for "${row.productName}" between ${row.importerName} and ${row.exporterName}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Force Close')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _service.adminForceClose(row.id);
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

  Future<void> _viewHistory(AdminNegotiationRow row) async {
    List<NegotiationOffer> offers = [];
    String? error;
    try {
      offers = await _service.getHistory(row.id);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Offer History — ${row.productName}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text('${row.importerName} ↔ ${row.exporterName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 12),
              if (error != null) Text('Error: $error', style: const TextStyle(color: AppColors.error)),
              Expanded(
                child: offers.isEmpty && error == null
                    ? const AdminEmptyState(icon: Icons.receipt_long_outlined, title: 'No offers recorded')
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: offers.length,
                        itemBuilder: (context, i) {
                          final o = offers[i];
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
                                    Expanded(child: Text('Round ${o.roundNumber} · ${o.createdBy}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                                    Text(o.status.toUpperCase(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('${o.currency} ${o.unitPrice} × ${o.quantity} = ${o.currency} ${o.totalPrice}', style: const TextStyle(fontSize: 12)),
                                if (o.remarks != null && o.remarks!.isNotEmpty)
                                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(o.remarks!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5))),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
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
      appBar: AdminGradientAppBar(title: 'Negotiation Center'),
      body: AdminPageBackground(
        child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AdminSearchField(
              hint: 'Search by RFQ #, product, importer, exporter',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _statusFilters
                    .map((s) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(_statusLabels[s]!, style: TextStyle(fontSize: 12, color: _statusFilter == s ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600)),
                            selected: _statusFilter == s,
                            onSelected: (_) {
                              setState(() => _statusFilter = s);
                              _refresh();
                            },
                            selectedColor: AppColors.primary,
                            backgroundColor: Theme.of(context).cardTheme.color,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<AdminNegotiationRow>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) {
                  return Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
                }
                var rows = snapshot.data ?? [];
                if (_query.trim().isNotEmpty) {
                  final q = _query.trim().toLowerCase();
                  rows = rows.where((r) =>
                      r.rfqNumber.toLowerCase().contains(q) ||
                      r.productName.toLowerCase().contains(q) ||
                      r.importerName.toLowerCase().contains(q) ||
                      r.exporterName.toLowerCase().contains(q)).toList();
                }
                if (rows.isEmpty) {
                  return const AdminEmptyState(
                    icon: Icons.handshake_outlined,
                    title: 'No negotiations found',
                    subtitle: 'Try adjusting your search or filter.',
                  );
                }
                return Column(
                  children: rows.asMap().entries.map((entry) {
                    final i = entry.key;
                    final row = entry.value;
                    final color = _statusColor(row.status);
                    return AdminReveal(
                      index: i,
                      child: AdminCard(
                      accent: color,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(row.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              AdminStatusBadge(label: row.status.toUpperCase(), color: color),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('${row.rfqNumber} · Round ${row.currentRound} · ${row.offerCount} offer(s)', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                          const SizedBox(height: 4),
                          Text('${row.importerName} ← ${row.exporterName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _viewHistory(row),
                                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8)),
                                  icon: const Icon(Icons.history, size: 14),
                                  label: const Text('View Timeline', style: TextStyle(fontSize: 12)),
                                ),
                              ),
                              if (row.status == 'open') ...[
                                const SizedBox(width: 6),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _busy ? null : () => _forceClose(row),
                                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8), foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                                    icon: const Icon(Icons.block, size: 14),
                                    label: const Text('Force Close', style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
        ),
      ),
    );
  }
}
