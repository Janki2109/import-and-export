import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_client.dart';
import '../../models/order.dart';
import '../../models/trade.dart';
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
    return DoubleBackToExit(child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Importer Dashboard'),
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
          _ProfileMenuButton(name: auth.currentUser?.fullName ?? 'Importer'),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _GradientFab(
        onPressed: () async {
          final result = await Navigator.of(context).push<Map<String, dynamic>>(
            MaterialPageRoute(builder: (_) => const CreateOrderScreen()),
          );
          if (result != null) {
            _startUpiPayment(result['order']['id'], result['upi_link'], (result['amount'] as num).toDouble());
          }
        },
        icon: Icons.add,
        label: 'New Order',
      ),
      body: RefreshIndicator(
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
                  ),
                ),
                SliverToBoxAdapter(
                  child: _StatsGrid(
                    orders: orders,
                    myRfqs: b?.myRfqs ?? [],
                    quotationsReceived: b?.quotationsReceived ?? 0,
                    walletBalance: b?.wallet?.balance ?? 0,
                    onOpenRfqs: () => _push(const MyRFQsScreen()),
                    onQuotations: () => _push(const MyRFQsScreen()),
                    onOrders: () => _scrollToOrders(),
                    onWallet: () => _push(const WalletScreen()),
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  sliver: SliverToBoxAdapter(
                    key: _ordersKey,
                    child: _SectionHeader(icon: Icons.inventory_2_outlined, title: 'Your Orders'),
                  ),
                ),
                if (orders.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ImporterEmptyState(onCreateOrder: () => _push(const BrowseCatalogScreen())),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
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
      ),
    ));
  }

  final _ordersKey = GlobalKey();

  void _scrollToOrders() {
    final ctx = _ordersKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }
}

/// Top-right avatar -> profile/company/documents/settings/logout menu — same pattern as
/// the Exporter Dashboard's profile menu, importer-relevant destinations.
class _ProfileMenuButton extends ConsumerWidget {
  final String name;
  const _ProfileMenuButton({required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authProvider);
    return PopupMenuButton<String>(
      tooltip: 'Profile',
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        switch (value) {
          case 'profile':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
            break;
          case 'documents':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KYCScreen()));
            break;
          case 'catalog':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BrowseCatalogScreen()));
            break;
          case 'suppliers':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BrowseExportersScreen()));
            break;
          case 'membership':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MembershipScreen()));
            break;
          case 'ads':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdsScreen()));
            break;
          case 'disputes':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DisputesScreen()));
            break;
          case 'logout':
            auth.logout();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profile'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'documents', child: ListTile(leading: Icon(Icons.description_outlined), title: Text('Documents / KYC'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'catalog', child: ListTile(leading: Icon(Icons.storefront_outlined), title: Text('Browse Catalog'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'suppliers', child: ListTile(leading: Icon(Icons.business_outlined), title: Text('Find Suppliers'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'membership', child: ListTile(leading: Icon(Icons.workspace_premium_outlined), title: Text('Membership'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'ads', child: ListTile(leading: Icon(Icons.campaign_outlined), title: Text('Advertisements'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'disputes', child: ListTile(leading: Icon(Icons.gavel_outlined), title: Text('My Disputes'), contentPadding: EdgeInsets.zero)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout, color: AppColors.error), title: Text('Logout', style: TextStyle(color: AppColors.error)), contentPadding: EdgeInsets.zero)),
      ],
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
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          borderRadius: widget.borderRadius,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: widget.borderRadius,
            child: widget.child,
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
  const _WelcomeCard({
    required this.name,
    this.avatarUrl,
    this.companyName,
    this.country,
    required this.roleLabel,
    required this.verified,
    required this.completionPercent,
    required this.onCompleteProfile,
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
          ],
        ),
      ),
    );
  }
}

/// 8-card, 2-column statistics grid — all figures derived from real, already-fetched data
/// (orders list + RFQ list + wallet summary). No fabricated numbers.
class _StatsGrid extends StatelessWidget {
  final List<dynamic> orders;
  final List<RFQ> myRfqs;
  final int quotationsReceived;
  final double walletBalance;
  final VoidCallback onOpenRfqs;
  final VoidCallback onQuotations;
  final VoidCallback onOrders;
  final VoidCallback onWallet;
  const _StatsGrid({
    required this.orders,
    required this.myRfqs,
    required this.quotationsReceived,
    required this.walletBalance,
    required this.onOpenRfqs,
    required this.onQuotations,
    required this.onOrders,
    required this.onWallet,
  });

  @override
  Widget build(BuildContext context) {
    final activeRfqs = myRfqs.where((r) => r.status == 'open' || r.status == 'quoted').length;
    final activeShipments = orders.where((o) => ['accepted', 'shipped', 'in_transit'].contains(o['status'])).length;
    final escrowAmount = orders
        .where((o) => o['status'] == 'payment_held')
        .fold<double>(0, (sum, o) => sum + (double.tryParse('${o['total_amount']}') ?? 0));
    final completedOrders = orders.where((o) => o['status'] == 'payment_released').length;

    final items = [
      ('Active RFQs', activeRfqs.toDouble(), '$activeRfqs', Icons.request_quote_outlined, AppColors.primary, onOpenRfqs),
      ('Quotations Received', quotationsReceived.toDouble(), '$quotationsReceived', Icons.description_outlined, Colors.purple, onQuotations),
      ('Orders', orders.length.toDouble(), '${orders.length}', Icons.inventory_2_outlined, AppColors.accent, onOrders),
      ('Active Shipments', activeShipments.toDouble(), '$activeShipments', Icons.local_shipping_outlined, AppColors.heldBlue, onOrders),
      ('Wallet Balance', walletBalance, '₹${walletBalance.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined, AppColors.success, onWallet),
      ('Escrow Payments', escrowAmount, '₹${escrowAmount.toStringAsFixed(0)}', Icons.lock_clock_outlined, AppColors.warning, onOrders),
      ('Completed Orders', completedOrders.toDouble(), '$completedOrders', Icons.task_alt_outlined, AppColors.success, onOrders),
      ('Total RFQs', myRfqs.length.toDouble(), '${myRfqs.length}', Icons.receipt_long_outlined, Colors.purple, onOpenRfqs),
    ];

    const crossAxisCount = 2;
    const spacing = 10.0;
    const targetCardHeight = 128.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
          final aspectRatio = cellWidth / targetCardHeight;
          return GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
            children: [
              for (int i = 0; i < items.length; i++)
                _Reveal(
                  index: i,
                  child: _StatCard(label: items[i].$1, value: items[i].$3, icon: items[i].$4, color: items[i].$5, onTap: items[i].$6),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _TapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.10)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(height: 8),
            // FittedBox scales the value down instead of overflowing/clipping for large
            // figures (e.g. big wallet/escrow amounts) — never shrinks below its natural
            // size for normal short values.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.3), maxLines: 1),
            ),
            const SizedBox(height: 4),
            // Expanded + maxLines:2 lets the label wrap to a second line and absorbs any
            // remaining card height, so it can never push the card past its fixed height.
            Expanded(
              child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
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
      (Icons.add_box_outlined, 'Create RFQ', onCreateRfq, AppColors.primary),
      (Icons.request_quote_outlined, 'My RFQs', onMyRfqs, AppColors.secondary),
      (Icons.description_outlined, 'Quotations', onQuotations, Colors.purple),
      (Icons.inventory_2_outlined, 'Orders', onOrders, AppColors.accent),
      (Icons.local_shipping_outlined, 'Shipments', onShipments, AppColors.heldBlue),
      (Icons.account_balance_wallet_outlined, 'Wallet', onWallet, AppColors.success),
      (Icons.chat_bubble_outline, 'Messages', onMessages, AppColors.warning),
      (Icons.travel_explore_outlined, 'Trade Tools', onTradeTools, AppColors.primary),
      if (onNegotiations != null) (Icons.handshake_outlined, 'Negotiations', onNegotiations!, AppColors.secondary),
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
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
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
            ElevatedButton.icon(
              onPressed: onLaunchUpi,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Pay via UPI App'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onPaymentDone,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Payment Done'),
            ),
          ],
        ),
      ),
    );
  }
}
