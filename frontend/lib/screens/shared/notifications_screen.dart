import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/notification_service.dart';

const _categories = ['All', 'Orders', 'Payments', 'Messages', 'RFQs', 'Shipment', 'Wallet'];

/// Maps a notification's `type` (as sent by NotificationService on the backend) into one
/// of the requested display categories.
String _categoryOf(String type) {
  switch (type) {
    case 'order_update':
      return 'Orders';
    case 'escrow':
    case 'wallet':
      return type == 'wallet' ? 'Wallet' : 'Payments';
    case 'message':
      return 'Messages';
    case 'rfq':
    case 'quotation':
      return 'RFQs';
    case 'shipment':
      return 'Shipment';
    default:
      return 'All';
  }
}

(IconData, Color) _iconFor(String category) {
  switch (category) {
    case 'Orders':
      return (Icons.inventory_2_outlined, AppColors.accent);
    case 'Payments':
      return (Icons.payments_outlined, AppColors.success);
    case 'Messages':
      return (Icons.chat_bubble_outline, AppColors.heldBlue);
    case 'RFQs':
      return (Icons.request_quote_outlined, AppColors.primary);
    case 'Shipment':
      return (Icons.local_shipping_outlined, AppColors.warning);
    case 'Wallet':
      return (Icons.account_balance_wallet_outlined, AppColors.success);
    default:
      return (Icons.notifications_outlined, AppColors.primary);
  }
}

/// Shared notifications inbox — reads/marks-read via the existing `/notifications` API.
/// Category tabs are computed client-side from each notification's `type` field.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  late Future<List<dynamic>> _future;
  String _category = 'All';

  @override
  void initState() {
    super.initState();
    _future = _service.list();
  }

  void _refresh() => setState(() => _future = _service.list());

  Future<void> _markAllRead(List<dynamic> notifications) async {
    final unread = notifications.where((n) => n['is_read'] != true).toList();
    for (final n in unread) {
      // ignore: unawaited_futures
      _service.markRead(n['id']);
    }
    if (mounted) {
      setState(() {
      for (final n in notifications) {
        n['is_read'] = true;
      }
    });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          FutureBuilder<List<dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              final list = snapshot.data ?? [];
              final hasUnread = list.any((n) => n['is_read'] != true);
              return TextButton(
                onPressed: hasUnread ? () => _markAllRead(list) : null,
                child: Text('Mark All Read', style: TextStyle(color: hasUnread ? Colors.white : Colors.white.withValues(alpha: 0.4))),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final all = snapshot.data ?? [];
            final filtered = _category == 'All' ? all : all.where((n) => _categoryOf(n['type'] ?? '') == _category).toList();

            return Column(
              children: [
                SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    children: _categories.map((c) {
                      final count = c == 'All' ? all.where((n) => n['is_read'] != true).length : all.where((n) => _categoryOf(n['type'] ?? '') == c && n['is_read'] != true).length;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(c, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _category == c ? Colors.white : AppColors.textPrimary)),
                              if (count > 0) ...[
                                const SizedBox(width: 5),
                                CircleAvatar(radius: 8, backgroundColor: _category == c ? Colors.white : AppColors.error, child: Text('$count', style: TextStyle(fontSize: 9, color: _category == c ? AppColors.primary : Colors.white, fontWeight: FontWeight.w700))),
                              ],
                            ],
                          ),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                          selectedColor: AppColors.primary,
                          backgroundColor: Theme.of(context).cardTheme.color,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const _EmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final n = filtered[i];
                            final category = _categoryOf(n['type'] ?? '');
                            final (icon, color) = _iconFor(category);
                            final isRead = n['is_read'] == true;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: isRead ? Theme.of(context).cardTheme.color : color.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: isRead ? Colors.grey.shade200 : color.withValues(alpha: 0.25)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                                  child: Icon(icon, color: color, size: 20),
                                ),
                                title: Text(n['title'] ?? '', style: TextStyle(fontWeight: isRead ? FontWeight.w600 : FontWeight.w800, fontSize: 13.5)),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(n['body'] ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                ),
                                trailing: !isRead ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)) : null,
                                onTap: () async {
                                  if (!isRead) {
                                    await _service.markRead(n['id']);
                                    if (mounted) setState(() => n['is_read'] = true);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              child: const Icon(Icons.notifications_none_outlined, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text('No Notifications', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            const Text("You're all caught up. New updates will show up here.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
