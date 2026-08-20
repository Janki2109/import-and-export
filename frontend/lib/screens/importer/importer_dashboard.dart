import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_client.dart';
import '../../models/order.dart';
import '../../models/trade.dart';
import '../../providers/auth_provider.dart';
import '../../providers/providers.dart';
import '../../services/company_service.dart';
import '../../services/kyc_service.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';
import '../../services/trade_service.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/double_back_to_exit.dart';
import '../chat/conversations_screen.dart';
import '../profile/profile_screen.dart';
import '../search/trade_tools_screen.dart';
import '../shared/ads_screen.dart';
import '../shared/disputes_screen.dart';
import '../shared/kyc_screen.dart';
import '../shared/membership_screen.dart';
import '../shared/my_negotiations_screen.dart';
import '../shared/notifications_screen.dart';
import '../shared/order_details_screen.dart';
import '../shared/order_documents_screen.dart';
import '../wallet/wallet_screen.dart';
import '../../widgets/premium_background.dart';
import '../../widgets/theme_toggle_button.dart';
import 'browse_catalog_screen.dart';
import 'browse_exporters_screen.dart';
import 'create_order_screen.dart';
import 'create_rfq_screen.dart';
import 'my_rfqs_screen.dart';
import 'rfq_details_screen.dart';

/// Importer's home: shows their orders, lets them pay (escrow hold) and later
/// confirm delivery (escrow release) once goods arrive.
///
/// UI-ONLY REDESIGN: every widget below still reads exactly the same _DashboardBundle
/// fields, calls exactly the same callbacks/services, and pushes exactly the same screens
/// as before — only presentation (gradients, shadows, motion, typography, spacing) changed.
class ImporterDashboard extends ConsumerStatefulWidget {
  const ImporterDashboard({super.key});
  @override
  ConsumerState<ImporterDashboard> createState() => _ImporterDashboardState();
}

/// Everything the dashboard's top section needs, fetched in parallel so the hero/stat
/// cards appear together. Quotations Received is a real aggregate — summed from
/// listQuotationsForRFQ() across every one of the importer's own RFQs (there's no single
/// backend endpoint for "all quotations across my RFQs", so this composes the existing
/// per-RFQ endpoint instead of fabricating a number).
class _DashboardBundle {
  final bool kycVerified;
  final String? country;
  final int completionPercent;
  final List<RFQ> myRfqs;
  final int quotationsReceived;
  final List<dynamic> orders;
  final WalletSummary? wallet;
  final List<dynamic> notifications;
  const _DashboardBundle({
    required this.kycVerified,
    required this.country,
    required this.completionPercent,
    required this.myRfqs,
    required this.quotationsReceived,
    required this.orders,
    required this.wallet,
    required this.notifications,
  });
}

class _ImporterDashboardState extends ConsumerState<ImporterDashboard> {
  final _orderService = OrderService();
  final _tradeService = TradeService();
  final _companyService = CompanyService();
  final _kycService = KYCService();
  final _notificationService = NotificationService();

  late Future<_DashboardBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _refresh() => setState(() => _future = _load());

  Future<_DashboardBundle> _load() async {
    final results = await Future.wait([
      ApiClient().get('/orders').then((r) => r.data['data'] ?? []).catchError((_) => []),
      _tradeService.listMyRFQs().catchError((_) => <RFQ>[]),
      _tradeService.getMyWallet().catchError((_) => WalletSummary(balance: 0, transactions: [])),
      _companyService.getMine().catchError((_) => null),
      _kycService.getMyStatus().catchError((_) => <String, dynamic>{}),
      _notificationService.list().catchError((_) => []),
    ]);

    final orders = results[0] as List<dynamic>;
    final myRfqs = results[1] as List<RFQ>;
    final wallet = results[2] as WalletSummary?;
    final company = results[3];
    final kyc = results[4] as Map<String, dynamic>;

    final companyDone = company != null;
    final kycStatus = kyc['status'] as String?;
    final kycSubmitted = kyc.isNotEmpty;
    final kycApproved = kycStatus == 'verified';
    final steps = [companyDone, kycSubmitted, kycApproved];
    final completion = ((steps.where((s) => s).length / steps.length) * 100).round();

    // Aggregate quotations across every RFQ this importer has posted.
    int quotationsReceived = 0;
    try {
      final quotationLists = await Future.wait(
        myRfqs.map((r) => _tradeService.listQuotationsForRFQ(r.id).catchError((_) => <Quotation>[])),
      );
      quotationsReceived = quotationLists.fold<int>(0, (sum, list) => sum + list.length);
    } catch (_) {
      quotationsReceived = 0;
    }

    return _DashboardBundle(
      kycVerified: kycApproved,
      country: company?.country,
      completionPercent: completion,
      myRfqs: myRfqs,
      quotationsReceived: quotationsReceived,
      orders: orders,
      wallet: wallet,
      notifications: results[5] as List<dynamic>,
    );
  }

  /// Called from CreateOrderScreen after backend creates the order + a upi://pay link.
  /// Opens the user's UPI app (GPay/PhonePe/etc); when they return, they tap "Payment Done"
  /// to self-declare the payment — there's no gateway callback to listen for.
  Future<void> _startUpiPayment(String orderId, String upiLink, double amount) async {
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      builder: (ctx) => _PaymentSheet(
        amount: amount,
        upiLink: upiLink,
        onLaunchUpi: () async {
          final uri = Uri.parse(upiLink);
          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!ok && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('No UPI app found. Install GPay, PhonePe, or another UPI app.')),
            );
          }
        },
        onPaymentDone: () async {
          Navigator.pop(ctx);
          try {
            await _orderService.confirmPayment(orderId: orderId);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment recorded ✅ Exporter notified to ship.'), backgroundColor: AppColors.success),
              );
              _refresh();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not confirm payment: $e'), backgroundColor: AppColors.error),
              );
            }
          }
        },
      ),
    );
  }

  /// Shipment marked "Delivered" — importer chooses to confirm (releases escrow) or report
  /// an issue (opens the existing dispute flow) instead of only offering one option.
  Future<void> _confirmDelivery(String orderId) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Order Delivered'),
        content: const Text("Has this order arrived in good condition? Confirming releases the held payment for the exporter."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'issue'),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Report Issue'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'confirm'), child: const Text('Confirm Delivery')),
        ],
      ),
    );
    if (choice == 'issue') {
      if (!mounted) return;
      await showRaiseDisputeDialog(context, orderId);
      if (mounted) _refresh();
      return;
    }
    if (choice != 'confirm') return;

    try {
      await _orderService.confirmDelivery(orderId: orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery confirmed. Payment release approved for the exporter.'), backgroundColor: AppColors.success),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColors = isDark ? [AppColorsDark.primary, AppColorsDark.secondary] : [const Color(0xFF0B3D91), const Color(0xFF1857C4)];
    return DoubleBackToExit(child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Importer Dashboard'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: headerColors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        ),
        actions: [
          const ThemeToggleButton(),
          FutureBuilder<_DashboardBundle>(
            future: _future,
            builder: (context, snapshot) {
              final unread = (snapshot.data?.notifications ?? []).where((n) => n['is_read'] != true).length;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: 'Notifications',
                    onPressed: () async {
                      await _push(const NotificationsScreen());
                      _refresh();
                    },
                  ),
                  if (unread > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text('$unread', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              );
            },
          ),
          FutureBuilder<_DashboardBundle>(
            future: _future,
            builder: (context, snapshot) => _ProfileMenuButton(
              name: auth.currentUser?.fullName ?? 'Importer',
              email: auth.currentUser?.email ?? '',
              verified: snapshot.data?.kycVerified ?? false,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PremiumPageBackground(child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<_DashboardBundle>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _DashboardSkeleton();
            }
            final b = snapshot.data;
            final orders = b?.orders ?? [];
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _WelcomeCard(
                    name: auth.currentUser?.fullName ?? 'Importer',
                    avatarUrl: auth.currentUser?.avatarUrl,
                    companyName: auth.currentUser?.companyName,
                    country: b?.country,
                    roleLabel: 'Importer',
                    verified: b?.kycVerified ?? false,
                    completionPercent: b?.completionPercent ?? 0,
                    onCompleteProfile: () => _push(const KYCScreen()),
                    onViewProfile: () => _push(const ProfileScreen()),
                  ),
                ),
                if (b != null && b.notifications.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _RecentNotifications(
                      notifications: b.notifications.take(3).toList(),
                      onSeeAll: () async {
                        await _push(const NotificationsScreen());
                        _refresh();
                      },
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _QuickActionsGrid(
                    onCreateRfq: () => _push(const CreateRFQScreen()),
                    onMyRfqs: () => _push(const MyRFQsScreen()),
                    onQuotations: () => _push(const MyRFQsScreen()),
                    onOrders: () => _scrollToOrders(),
                    onShipments: () => _scrollToOrders(),
                    onWallet: () => _push(const WalletScreen()),
                    onMessages: () => _push(const ConversationsScreen()),
                    onTradeTools: () => _push(const TradeToolsScreen()),
                    onNegotiations: () => _push(const MyNegotiationsScreen()),
                  ),
                ),
                if (b != null && (b.myRfqs.isNotEmpty || orders.isNotEmpty))
                  SliverToBoxAdapter(
                    child: _RecentActivity(myRfqs: b.myRfqs, orders: orders),
                  ),
                SliverToBoxAdapter(
                  key: _ordersKey,
                  child: _OrdersSummaryCard(
                    orders: orders,
                    onNewOrder: () async {
                      final result = await Navigator.of(context).push<Map<String, dynamic>>(
                        MaterialPageRoute(builder: (_) => const CreateOrderScreen()),
                      );
                      if (result != null) {
                        _startUpiPayment(result['order']['id'], result['upi_link'], (result['amount'] as num).toDouble());
                      }
                    },
                  ),
                ),
                if (orders.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ImporterEmptyState(onCreateOrder: () => _push(const BrowseCatalogScreen())),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                    sliver: SliverList.builder(
                      itemCount: orders.length,
                      itemBuilder: (context, i) {
                        final o = orders[i];
                        final status = o['status'] as String? ?? 'created';
                        return _OrderCard(
                          index: i,
                          title: o['product_name'] ?? '',
                          subtitle: '${o['order_number']} · ₹${o['total_amount']}',
                          status: status,
                          trailingActions: [
                            if (!['payment_released', 'refunded', 'cancelled', 'disputed'].contains(status))
                              IconButton(
                                icon: const Icon(Icons.report_problem_outlined, size: 20),
                                tooltip: 'Raise Dispute',
                                onPressed: () => showRaiseDisputeDialog(context, o['id']),
                              ),
                            IconButton(
                              icon: const Icon(Icons.description_outlined, size: 20),
                              tooltip: 'Documents',
                              onPressed: () => _push(OrderDocumentsScreen(orderId: o['id'])),
                            ),
                            IconButton(
                              icon: const Icon(Icons.visibility_outlined, size: 20),
                              tooltip: 'Order Details',
                              onPressed: () => _push(OrderDetailsScreen(order: Order.fromJson(o))),
                            ),
                          ],
                          onTap: status == 'delivered' ? () => _confirmDelivery(o['id']) : null,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      )),
      bottomNavigationBar: _PremiumBottomNav(
        activeIndex: 0,
        items: const [
          (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
          (Icons.request_quote_outlined, Icons.request_quote, 'RFQs'),
          (Icons.inventory_2_outlined, Icons.inventory_2, 'Orders'),
          (Icons.local_shipping_outlined, Icons.local_shipping, 'Shipments'),
          (Icons.receipt_long_outlined, Icons.receipt_long, 'Transactions'),
          (Icons.person_outline, Icons.person, 'Profile'),
        ],
        onTap: (i) {
          switch (i) {
            case 1:
              _push(const MyRFQsScreen());
              break;
            case 2:
            case 3:
              _scrollToOrders();
              break;
            case 4:
              _push(const WalletScreen());
              break;
            case 5:
              _push(const ProfileScreen());
              break;
          }
        },
      ),
    ));
  }

  final _ordersKey = GlobalKey();

  void _scrollToOrders() {
    final ctx = _ordersKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }
}

/// Top-right avatar -> profile/company/documents/settings/logout menu — same destinations,
/// same routes, same logout call as before; only presentation changed to a premium
/// slide-in panel (see [_ProfileMenuPanel]) instead of a plain PopupMenuButton.
class _ProfileMenuButton extends ConsumerWidget {
  final String name;
  final String email;
  final bool verified;
  const _ProfileMenuButton({required this.name, required this.email, required this.verified});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authProvider);
    return InkWell(
      onTap: () => _openProfileMenu(context, auth, name: name, email: email, verified: verified),
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.4)),
          child: CircleAvatar(
            radius: 15,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
      ),
    );
  }
}

void _openProfileMenu(BuildContext context, AuthProvider auth, {required String name, required String email, required bool verified}) {
  // Anchored near the top-right avatar button — a side panel, not a full-width bar.
  final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;
  showGeneralDialog(
    context: context,
    barrierLabel: 'Profile menu',
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return Stack(
        children: [
          Positioned(
            top: topInset + 6,
            right: 12,
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                alignment: Alignment.topRight,
                scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
                child: _ProfileMenuPanel(name: name, email: email, verified: verified, auth: auth),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
  );
}

/// Premium profile drawer — gradient header (avatar, name, email, verification badge) plus
/// a scrollable list of the exact same menu items/routes/actions the old PopupMenuButton
/// exposed. Slides in from the top-right, dims the dashboard behind it, dismisses on
/// outside tap or after any item is selected.
class _ProfileMenuPanel extends StatelessWidget {
  final String name;
  final String email;
  final bool verified;
  final AuthProvider auth;
  const _ProfileMenuPanel({required this.name, required this.email, required this.verified, required this.auth});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.person_outline, 'Profile', 'View and edit your profile', const Color(0xFF2563EB), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()))),
      (Icons.description_outlined, 'Documents / KYC', 'Manage your documents', const Color(0xFFDB2777), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KYCScreen()))),
      (Icons.storefront_outlined, 'Browse Catalog', 'Explore products & services', const Color(0xFFEA580C), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BrowseCatalogScreen()))),
      (Icons.business_outlined, 'Find Suppliers', 'Discover verified suppliers', const Color(0xFF7C3AED), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BrowseExportersScreen()))),
      (Icons.workspace_premium_outlined, 'Membership', 'Manage your membership', const Color(0xFF0D9488), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MembershipScreen()))),
      (Icons.campaign_outlined, 'Advertisements', 'Manage your ads', const Color(0xFF2563EB), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdsScreen()))),
      (Icons.gavel_outlined, 'My Disputes', 'View and track disputes', const Color(0xFFCA8A04), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DisputesScreen()))),
    ];

    // Side panel anchored near the top-right avatar button — not full device width.
    final maxHeight = MediaQuery.of(context).size.height * 0.82;
    final width = MediaQuery.of(context).size.width * 0.78;
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: width),
        child: Container(
          width: width,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 26, offset: const Offset(0, 10))],
          ),
          child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                        child: Column(
                          children: [
                            for (int i = 0; i < items.length; i++)
                              _Reveal(
                                index: i,
                                base: const Duration(milliseconds: 160),
                                child: _ProfileMenuTile(
                                  icon: items[i].$1,
                                  title: items[i].$2,
                                  subtitle: items[i].$3,
                                  color: items[i].$4,
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    items[i].$5();
                                  },
                                ),
                              ),
                            const SizedBox(height: 6),
                            _ProfileMenuTile(
                              icon: Icons.logout,
                              title: 'Logout',
                              subtitle: 'Securely sign out',
                              color: AppColors.error,
                              danger: true,
                              onTap: () {
                                Navigator.of(context).pop();
                                auth.logout();
                              },
                            ),
                            const SizedBox(height: 12),
                            _TapScale(
                              onTap: () {
                                Navigator.of(context).pop();
                                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MembershipScreen()));
                              },
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [const Color(0xFF7C3AED).withValues(alpha: 0.1), const Color(0xFF2563EB).withValues(alpha: 0.08)]),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.18)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.workspace_premium, color: Color(0xFF7C3AED), size: 26),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Go Premium', style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w800, fontSize: 14)),
                                          SizedBox(height: 2),
                                          Text('Unlock more features and grow your business', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                      child: const Icon(Icons.arrow_forward, size: 15, color: Color(0xFF7C3AED)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool danger;
  const _ProfileMenuTile({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _TapScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: danger ? AppColors.error.withValues(alpha: 0.06) : Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: danger ? Border.all(color: AppColors.error.withValues(alpha: 0.15)) : null,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: danger ? AppColors.error : null), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 1),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: danger ? AppColors.error.withValues(alpha: 0.6) : AppColors.textSecondary.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Shared premium building blocks (dashboard-local — presentation only).
// ============================================================================

/// Press-scale micro-interaction wrapper — shrinks slightly on press, springs back on
/// release. Wraps existing tap targets without changing what they do.
class _TapScale extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final BorderRadius? borderRadius;
  const _TapScale({required this.onTap, required this.child, this.borderRadius});

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: Material(
            color: Colors.transparent,
            borderRadius: widget.borderRadius,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: widget.borderRadius,
              splashColor: AppColors.primary.withValues(alpha: 0.15),
              highlightColor: AppColors.primary.withValues(alpha: 0.08),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Staggered entrance — fade + slide-up + slight scale, delayed by [index]. Used for every
/// card grid/list on the dashboard so content builds in smoothly instead of popping in.
class _Reveal extends StatelessWidget {
  final int index;
  final Widget child;
  final Duration base;
  const _Reveal({required this.index, required this.child, this.base = const Duration(milliseconds: 260)});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: base + Duration(milliseconds: (index * 40).clamp(0, 320)),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: Transform.scale(scale: 0.97 + 0.03 * v, child: c)),
      ),
      child: child,
    );
  }
}

/// Premium bottom navigation — visual only. It does NOT introduce new routes: "Dashboard" is
/// always the active tab (this bar only ever renders on the dashboard screen itself), and
/// every other item just triggers the exact same push/scroll callback the equivalent Quick
/// Action already uses — a shortcut, not a new navigation destination.
class _PremiumBottomNav extends StatelessWidget {
  final int activeIndex;
  final List<(IconData, IconData, String)> items;
  final void Function(int index) onTap;
  const _PremiumBottomNav({required this.activeIndex, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++)
              Expanded(
                child: _TapScale(
                  onTap: i == activeIndex ? null : () => onTap(i),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: i == activeIndex ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(i == activeIndex ? items[i].$2 : items[i].$1, size: 20, color: i == activeIndex ? AppColors.primary : AppColors.textSecondary),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9, fontWeight: i == activeIndex ? FontWeight.w700 : FontWeight.w500, color: i == activeIndex ? AppColors.primary : AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Section title with a small colored icon badge — used above every content block for a
/// consistent, premium visual hierarchy.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 15, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        ),
      ],
    );
  }
}

/// A vivid, gradient-filled action button with press micro-interaction — used for the
/// dashboard's primary actions (payment sheet, order-card buttons) instead of flat
/// Material buttons, for a more colorful, tactile feel.
class _GradientActionButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  final List<Color> colors;
  final bool outlined;
  const _GradientActionButton({required this.onTap, required this.icon, required this.label, required this.colors, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return _TapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: outlined ? null : LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          color: outlined ? colors.first.withValues(alpha: 0.08) : null,
          border: outlined ? Border.all(color: colors.first.withValues(alpha: 0.4), width: 1.4) : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: outlined ? null : [BoxShadow(color: colors.first.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: outlined ? colors.first : Colors.white),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: outlined ? colors.first : Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}

/// Floating action button with a soft gradient fill matching the hero card's palette.
class _GradientFab extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  const _GradientFab({required this.onPressed, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? [AppColorsDark.primary, AppColorsDark.secondary] : [const Color(0xFF0B3D91), const Color(0xFF1857C4)];
    return _TapScale(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
          ],
        ),
      ),
    );
  }
}

/// Subtle decorative backdrop for the hero/welcome card — two soft translucent circles,
/// purely visual (no interaction, no data).
class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -40,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            Positioned(
              right: 30,
              bottom: -50,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Welcome card — name, company, country, verified badge, and profile completion ring.
class _WelcomeCard extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String? companyName;
  final String? country;
  final String roleLabel;
  final bool verified;
  final int completionPercent;
  final VoidCallback onCompleteProfile;
  final VoidCallback onViewProfile;
  const _WelcomeCard({
    required this.name,
    this.avatarUrl,
    this.companyName,
    this.country,
    required this.roleLabel,
    required this.verified,
    required this.completionPercent,
    required this.onCompleteProfile,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark
        ? [AppColorsDark.primary, AppColorsDark.secondary, AppColorsDark.secondary]
        : [const Color(0xFF0B3D91), const Color(0xFF1657C0), const Color(0xFF1857C4)];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: Transform.scale(scale: 0.98 + 0.02 * v, child: child)),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        padding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.38), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        child: Stack(
          children: [
            const _HeroBackdrop(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.6)),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl!) : null,
                    child: avatarUrl == null
                        ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Flexible(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 18.5, fontWeight: FontWeight.w800, letterSpacing: -0.3), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (verified) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified, color: Color(0xFF6FE3A5), size: 18),
                          ],
                        ],
                      ),
                      if (companyName != null && companyName!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(companyName!, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      const SizedBox(height: 9),
                      // Wrap (not Row) so the verification badge drops to a second line instead
                      // of overflowing past the card edge / under the progress circle when the
                      // country name is long or the card is narrow.
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (country != null && country!.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on_outlined, size: 13, color: Colors.white.withValues(alpha: 0.8)),
                                const SizedBox(width: 3),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 140),
                                  child: Text(country!, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: verified ? const Color(0xFF6FE3A5).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: verified ? const Color(0xFF6FE3A5).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.25), width: 1),
                            ),
                            child: Text(
                              verified ? 'Verified $roleLabel' : 'Verification Pending',
                              style: TextStyle(color: verified ? const Color(0xFF6FE3A5) : Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _TapScale(
                  onTap: completionPercent < 100 ? onCompleteProfile : null,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: completionPercent / 100),
                                duration: const Duration(milliseconds: 900),
                                curve: Curves.easeOutCubic,
                                builder: (context, val, _) => CircularProgressIndicator(
                                  value: val,
                                  strokeWidth: 5,
                                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                                  valueColor: const AlwaysStoppedAnimation(Color(0xFF6FE3A5)),
                                ),
                              ),
                              Text('$completionPercent%', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text('Profile', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 9.5)),
                      ],
                    ),
                  ),
                ),
              ],
                ),
                const SizedBox(height: 14),
                _TapScale(
                  onTap: onViewProfile,
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('View Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward, color: Colors.white, size: 15),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dark "Your Orders" summary card — a real, honest breakdown of the same `orders` list
/// already fetched for the list below (Pending = just created, Confirmed = accepted/escrow
/// held, Shipped = shipped/in transit, Completed = payment released), with the existing
/// "New Order" action embedded as a floating pill instead of a separate Scaffold FAB.
class _OrdersSummaryCard extends StatelessWidget {
  final List<dynamic> orders;
  final VoidCallback onNewOrder;
  const _OrdersSummaryCard({required this.orders, required this.onNewOrder});

  @override
  Widget build(BuildContext context) {
    final pending = orders.where((o) => o['status'] == 'created').length;
    final confirmed = orders.where((o) => ['accepted', 'payment_held'].contains(o['status'])).length;
    final shipped = orders.where((o) => ['shipped', 'in_transit'].contains(o['status'])).length;
    final completed = orders.where((o) => ['payment_released', 'delivered'].contains(o['status'])).length;
    final items = [
      (Icons.hourglass_top_outlined, '$pending', 'Pending', const Color(0xFF60A5FA)),
      (Icons.check_circle_outline, '$confirmed', 'Confirmed', const Color(0xFF4ADE80)),
      (Icons.local_shipping_outlined, '$shipped', 'Shipped', const Color(0xFFFB923C)),
      (Icons.task_alt_outlined, '$completed', 'Completed', const Color(0xFFC084FC)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: _Reveal(
        index: 0,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0B1E45), Color(0xFF14306E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: const Color(0xFF0B1E45).withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.inventory_2_outlined, size: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        const Text('Your Orders', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        for (final it in items) ...[
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(color: it.$4.withValues(alpha: 0.18), shape: BoxShape.circle),
                                  child: Icon(it.$1, size: 16, color: it.$4),
                                ),
                                const SizedBox(height: 6),
                                Text(it.$2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(height: 2),
                                Text(it.$3, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
              Positioned(
                right: 8,
                bottom: -18,
                child: _GradientFab(onPressed: onNewOrder, icon: Icons.add, label: 'New Order'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentNotifications extends StatelessWidget {
  final List<dynamic> notifications;
  final VoidCallback onSeeAll;
  const _RecentNotifications({required this.notifications, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: _Reveal(
        index: 0,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.notifications_outlined, size: 14, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Recent Notifications', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                    TextButton(onPressed: onSeeAll, child: const Text('See All')),
                  ],
                ),
              ),
              ...notifications.map((n) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 6, right: 10),
                          decoration: BoxDecoration(color: n['is_read'] == true ? Colors.grey.shade300 : AppColors.primary, shape: BoxShape.circle),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(n['body'] ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  final VoidCallback onCreateRfq;
  final VoidCallback onMyRfqs;
  final VoidCallback onQuotations;
  final VoidCallback onOrders;
  final VoidCallback onShipments;
  final VoidCallback onWallet;
  final VoidCallback onMessages;
  final VoidCallback onTradeTools;
  final VoidCallback? onNegotiations;
  const _QuickActionsGrid({
    required this.onCreateRfq,
    required this.onMyRfqs,
    required this.onQuotations,
    required this.onOrders,
    required this.onShipments,
    required this.onWallet,
    required this.onMessages,
    required this.onTradeTools,
    this.onNegotiations,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.add_box_outlined, 'Create RFQ', onCreateRfq, const Color(0xFF2563EB)),
      (Icons.request_quote_outlined, 'My RFQs', onMyRfqs, const Color(0xFF7C3AED)),
      (Icons.description_outlined, 'Quotations', onQuotations, const Color(0xFFDB2777)),
      (Icons.inventory_2_outlined, 'Orders', onOrders, const Color(0xFFEA580C)),
      (Icons.local_shipping_outlined, 'Shipments', onShipments, const Color(0xFF0EA5E9)),
      (Icons.receipt_long_outlined, 'Transaction History', onWallet, const Color(0xFF16A34A)),
      (Icons.chat_bubble_outline, 'Messages', onMessages, const Color(0xFFCA8A04)),
      (Icons.travel_explore_outlined, 'Trade Tools', onTradeTools, const Color(0xFF0D9488)),
      if (onNegotiations != null) (Icons.handshake_outlined, 'Negotiations', onNegotiations!, const Color(0xFF9333EA)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.bolt_outlined, title: 'Quick Actions'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: [
              for (int i = 0; i < items.length; i++)
                _Reveal(
                  index: i,
                  base: const Duration(milliseconds: 200),
                  child: _QuickActionTile(icon: items[i].$1, label: items[i].$2, color: items[i].$4, onTap: items[i].$3),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickActionTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _TapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.14)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.16), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.65)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(height: 3, width: 22, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          ],
        ),
      ),
    );
  }
}

/// Latest RFQs + latest orders (whose status doubles as shipment status in this app —
/// there's no separate importer-facing shipment feed) — real data only, capped to 3 each.
class _RecentActivity extends StatelessWidget {
  final List<RFQ> myRfqs;
  final List<dynamic> orders;
  const _RecentActivity({required this.myRfqs, required this.orders});

  @override
  Widget build(BuildContext context) {
    final latestRfqs = [...myRfqs]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latestOrders = [...orders]..sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: _Reveal(
        index: 0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(icon: Icons.timeline_outlined, title: 'Recent Activity'),
              if (latestRfqs.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('LATEST RFQs', style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                const SizedBox(height: 6),
                ...latestRfqs.take(3).map((r) => _activityRow(
                      icon: Icons.request_quote_outlined,
                      title: r.productName,
                      status: r.status,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RFQDetailsScreen(rfq: r))),
                    )),
              ],
              if (latestOrders.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('LATEST ORDERS & SHIPMENT STATUS', style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                const SizedBox(height: 6),
                ...latestOrders.take(3).map((o) => _activityRow(icon: Icons.inventory_2_outlined, title: o['product_name'] ?? '', status: o['status'] ?? '')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _activityRow({required IconData icon, required String title, required String status, VoidCallback? onTap}) {
    final color = statusColor(status);
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(statusLabel(status), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: row);
  }
}

/// Order card used on the importer dashboard — leading product icon, title/subtitle,
/// status pill, and per-row quick actions.
class _OrderCard extends StatelessWidget {
  final int index;
  final String title;
  final String subtitle;
  final String status;
  final List<Widget> trailingActions;
  final VoidCallback? onTap;

  const _OrderCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.status,
    this.trailingActions = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return _Reveal(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: _TapScale(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.local_shipping_outlined, color: color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    ...trailingActions,
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatusBadge(status: status),
                    const Spacer(),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Professional empty state — icon, title, subtitle, and a real CTA (Browse Catalog).
class _ImporterEmptyState extends StatelessWidget {
  final VoidCallback onCreateOrder;
  const _ImporterEmptyState({required this.onCreateOrder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.9, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutBack,
              builder: (context, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.14), AppColors.primary.withValues(alpha: 0.04)]), shape: BoxShape.circle),
                child: const Icon(Icons.inventory_2_outlined, size: 44, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 18),
            const Text('No Orders Yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            const Text('Browse the product catalog or create an RFQ to receive quotations from exporters.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onCreateOrder,
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: const Text('Browse Catalog'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmering skeleton — an animated gradient sweep instead of flat grey placeholders,
/// for a smoother, more premium loading state.
class _ShimmerBox extends StatefulWidget {
  final double height;
  const _ShimmerBox(this.height);

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200;
    final sheen = Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.12) : Colors.grey.shade100;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Container(
            height: widget.height,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment(-1 + _controller.value * 3, 0),
                end: Alignment(_controller.value * 3, 0),
                colors: [base, sheen, base],
                stops: const [0.35, 0.5, 0.65],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _ShimmerBox(120),
        Row(children: const [Expanded(child: _ShimmerBox(76)), SizedBox(width: 10), Expanded(child: _ShimmerBox(76))]),
        Row(children: const [Expanded(child: _ShimmerBox(76)), SizedBox(width: 10), Expanded(child: _ShimmerBox(76))]),
        const _ShimmerBox(140),
        const _ShimmerBox(120),
      ],
    );
  }
}

/// Bottom sheet shown right after order creation: "Pay via UPI" opens the user's UPI app
/// (GPay/PhonePe/etc) with the amount pre-filled; "Payment Done" self-declares the payment
/// once they're back — there's no gateway callback to listen for.
class _PaymentSheet extends StatelessWidget {
  final double amount;
  final String upiLink;
  final VoidCallback onLaunchUpi;
  final VoidCallback onPaymentDone;

  const _PaymentSheet({
    required this.amount,
    required this.upiLink,
    required this.onLaunchUpi,
    required this.onPaymentDone,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pay ₹$amount via UPI', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Tap below to open GPay, PhonePe, or another UPI app. After paying, come back here and tap "Payment Done".',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _GradientActionButton(
              onTap: onLaunchUpi,
              icon: Icons.account_balance_wallet_outlined,
              label: 'Pay via UPI App',
              colors: const [Color(0xFF16A34A), Color(0xFF15803D)],
            ),
            const SizedBox(height: 12),
            _GradientActionButton(
              onTap: onPaymentDone,
              icon: Icons.check_circle_outline,
              label: 'Payment Done',
              colors: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
              outlined: true,
            ),
          ],
        ),
      ),
    );
  }
}
