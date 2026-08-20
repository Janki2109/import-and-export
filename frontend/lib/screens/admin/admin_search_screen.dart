import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';
import '../../widgets/admin_ui_kit.dart';

(IconData, Color) _categoryMeta(String category) {
  switch (category) {
    case 'Users':
      return (Icons.person_outline, const Color(0xFF2563EB));
    case 'Orders':
      return (Icons.receipt_long_outlined, const Color(0xFFEA580C));
    case 'RFQs':
      return (Icons.request_quote_outlined, const Color(0xFF7C3AED));
    case 'Shipments':
      return (Icons.local_shipping_outlined, const Color(0xFFCA8A04));
    case 'Wallet Transactions':
      return (Icons.account_balance_wallet_outlined, const Color(0xFF16A34A));
    default:
      return (Icons.search, const Color(0xFF0EA5E9));
  }
}

/// Global Search — one search bar across Users, Orders, RFQs, Shipments, and Wallet
/// Transactions. Backed by GET /admin/search?q=. Payments are represented via Orders
/// (which already carries escrow/payment status columns) rather than a separate index.
class AdminSearchScreen extends StatefulWidget {
  const AdminSearchScreen({super.key});
  @override
  State<AdminSearchScreen> createState() => _AdminSearchScreenState();
}

class _AdminSearchScreenState extends State<AdminSearchScreen> {
  final _adminService = AdminService();
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<List<AdminSearchResult>>? _future;

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _future = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _future = _adminService.globalSearch(q.trim()));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdminGradientAppBar(title: 'Global Search'),
      body: AdminPageBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: AdminSearchField(
                hint: 'Search importers, exporters, orders, RFQs, shipments, wallets…',
                controller: _controller,
                onChanged: _onChanged,
              ),
            ),
            Expanded(
              child: _future == null
                  ? const AdminEmptyState(
                      icon: Icons.travel_explore_outlined,
                      title: 'Start searching',
                      subtitle: 'Type at least 2 characters to search',
                    )
                  : FutureBuilder<List<AdminSearchResult>>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
                        }
                        final results = snapshot.data ?? [];
                        if (results.isEmpty) {
                          return const AdminEmptyState(
                            icon: Icons.search_off_outlined,
                            title: 'No results found',
                            subtitle: 'Try a different search term',
                          );
                        }
                        final grouped = <String, List<AdminSearchResult>>{};
                        for (final r in results) {
                          grouped.putIfAbsent(r.category, () => []).add(r);
                        }
                        int itemIndex = 0;
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: grouped.entries.map((entry) {
                            final (icon, color) = _categoryMeta(entry.key);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AdminSectionHeader(icon: icon, title: entry.key, color: color),
                                  const SizedBox(height: 10),
                                  ...entry.value.map((r) {
                                    final revealIndex = itemIndex++;
                                    return AdminReveal(
                                      index: revealIndex,
                                      child: AdminCard(
                                        accent: color,
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            AdminIconBadge(icon: icon, color: color, size: 34),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                  Text(r.subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
