import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';

(IconData, Color) _categoryMeta(String category) {
  switch (category) {
    case 'Users':
      return (Icons.person_outline, AppColors.primary);
    case 'Orders':
      return (Icons.receipt_long_outlined, AppColors.accent);
    case 'RFQs':
      return (Icons.request_quote_outlined, AppColors.secondary);
    case 'Shipments':
      return (Icons.local_shipping_outlined, AppColors.warning);
    case 'Wallet Transactions':
      return (Icons.account_balance_wallet_outlined, AppColors.success);
    default:
      return (Icons.search, AppColors.textSecondary);
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
      appBar: AppBar(title: const Text('Global Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search importers, exporters, orders, RFQs, shipments, wallets…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).cardTheme.color,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _future == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.travel_explore_outlined, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          const Text('Type at least 2 characters to search', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
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
                        return const Center(child: Text('No results found.', style: TextStyle(color: AppColors.textSecondary)));
                      }
                      final grouped = <String, List<AdminSearchResult>>{};
                      for (final r in results) {
                        grouped.putIfAbsent(r.category, () => []).add(r);
                      }
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: grouped.entries.map((entry) {
                          final (icon, color) = _categoryMeta(entry.key);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(icon, size: 15, color: color),
                                  const SizedBox(width: 6),
                                  Text(entry.key, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color)),
                                ]),
                                const SizedBox(height: 8),
                                ...entry.value.map((r) => Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardTheme.color,
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
                                      ),
                                      child: Row(
                                        children: [
                                          Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 16, color: color)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                Text(r.subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
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
    );
  }
}
