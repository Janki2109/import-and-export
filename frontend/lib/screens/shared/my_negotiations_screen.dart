import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/negotiation.dart';
import '../../services/negotiation_service.dart';
import '../../services/trade_service.dart';
import 'negotiation_screen.dart';

/// "My Negotiations" — shared inbox for both importer and exporter (each sees the ones
/// they're a party to, per ListMine's role-aware backend filter). Purely additive: new
/// screen, new service, no existing screen or navigation removed.
class MyNegotiationsScreen extends StatefulWidget {
  const MyNegotiationsScreen({super.key});
  @override
  State<MyNegotiationsScreen> createState() => _MyNegotiationsScreenState();
}

class _MyNegotiationsScreenState extends State<MyNegotiationsScreen> {
  final _negotiationService = NegotiationService();
  final _tradeService = TradeService();
  late Future<List<Negotiation>> _future;

  @override
  void initState() {
    super.initState();
    _future = _negotiationService.listMine();
  }

  void _refresh() => setState(() => _future = _negotiationService.listMine());

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

  Future<void> _open(Negotiation n) async {
    try {
      final rfq = await _tradeService.getRFQ(n.rfqId);
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NegotiationScreen(negotiationId: n.id, rfq: rfq)));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Negotiations')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Negotiation>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final negotiations = snapshot.data ?? [];
            if (negotiations.isEmpty) {
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
                        child: const Icon(Icons.handshake_outlined, size: 44, color: AppColors.primary),
                      ),
                      const SizedBox(height: 18),
                      const Text('No Negotiations Yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      const SizedBox(height: 8),
                      const Text('Start a negotiation from a quotation to see it here.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: negotiations.length,
              itemBuilder: (context, i) {
                final n = negotiations[i];
                final color = _statusColor(n.status);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _open(n),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                            child: Icon(Icons.handshake_outlined, color: color, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Round ${n.currentRound}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                Text(n.updatedAt.toLocal().toString().split(' ').first, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                            child: Text(n.status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
