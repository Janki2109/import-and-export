import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'browse_logistics_screen.dart';
import 'browse_rfqs_screen.dart';
import 'my_quotations_screen.dart';
import 'product_catalog_screen.dart';

/// UI-ONLY REDESIGN: every widget below still reads exactly the same _DashboardBundle
/// fields, calls exactly the same callbacks/services, and pushes exactly the same screens
/// as before — only presentation (gradients, shadows, motion, typography, spacing) changed.
class ExporterDashboard extends ConsumerStatefulWidget {
  const ExporterDashboard({super.key});
  @override
  ConsumerState<ExporterDashboard> createState() => _ExporterDashboardState();
}

/// Bundle of everything the dashboard's top section needs — fetched in parallel so the
/// hero/stat cards appear together rather than popping in one at a time.
class _DashboardBundle {
  final bool kycVerified;
  final String? country;
  final int completionPercent;
  final int openRfqCount;
  final int myQuotationCount;
  final List<dynamic> orders;
  final WalletSummary? wallet;
  final List<dynamic> notifications;
  const _DashboardBundle({
    required this.kycVerified,
    required this.country,
    required this.completionPercent,
    required this.openRfqCount,
    required this.myQuotationCount,
    required this.orders,
    required this.wallet,
    required this.notifications,
  });
}

class _ExporterDashboardState extends ConsumerState<ExporterDashboard> {
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
      ApiClient()
          .get('/orders')
          .then((r) => r.data['data'] ?? [])
          .catchError((_) => []),
      _tradeService.listOpenRFQs().catchError((_) => <RFQ>[]),
      _tradeService.listMyQuotations().catchError((_) => <Quotation>[]),
      _tradeService.getMyWallet().catchError((_) => WalletSummary(balance: 0, transactions: [])),
      _companyService.getMine().catchError((_) => null),
      _kycService.getMyStatus().catchError((_) => <String, dynamic>{}),
      _notificationService.list().catchError((_) => []),
    ]);

    final orders = results[0] as List<dynamic>;
    final openRfqs = results[1] as List<RFQ>;
    final myQuotations = results[2] as List<Quotation>;
    final wallet = results[3] as WalletSummary?;
    final company = results[4];
    final kyc = results[5] as Map<String, dynamic>;

    final companyDone = company != null;
    final kycStatus = kyc['status'] as String?;
    final kycSubmitted = kyc.isNotEmpty;
    final kycApproved = kycStatus == 'approved';
    final steps = [companyDone, kycSubmitted, kycApproved];
    final completion =
        ((steps.where((s) => s).length / steps.length) * 100).round();

    return _DashboardBundle(
      kycVerified: kycApproved,
      country: company?.country,
      completionPercent: completion,
      openRfqCount: openRfqs.length,
      myQuotationCount: myQuotations.length,
      orders: orders,
      wallet: wallet,
      notifications: results[6] as List<dynamic>,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return DoubleBackToExit(child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Exporter Dashboard'),
        actions: [
          const ThemeToggleButton(),
          FutureBuilder<_DashboardBundle>(
            future: _future,
            builder: (context, snapshot) {
              final unread = (snapshot.data?.notifications ?? [])
                  .where((n) => n['is_read'] != true)
                  .length;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: 'Notifications',
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const NotificationsScreen()));
                      _refresh();
                    },
                  ),
                  if (unread > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                            color: AppColors.error, shape: BoxShape.circle),
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text('$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              );
            },
          ),
          _ProfileMenuButton(name: auth.currentUser?.fullName ?? 'Exporter'),
          const SizedBox(width: 4),
        ],
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
                    name: auth.currentUser?.fullName ?? 'Exporter',
                    companyName: auth.currentUser?.companyName,
                    country: b?.country,
                    verified: b?.kycVerified ?? false,
                    completionPercent: b?.completionPercent ?? 0,
                    onCompleteProfile: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const KYCScreen())),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _QuickSummaryGrid(
                    openRfqs: b?.openRfqCount ?? 0,
                    myQuotations: b?.myQuotationCount ?? 0,
                    orders: orders.length,
                    walletBalance: b?.wallet?.balance ?? 0,
                    pendingPayments: b?.wallet?.pendingRelease ?? 0,
                    onOpenRfqs: () => _push(const BrowseRFQsScreen()),
                    onQuotations: () => _push(const MyQuotationsScreen()),
                    onOrders: () => _scrollToOrders(),
                    onWallet: () => _push(const WalletScreen()),
                  ),
                ),
                if (b != null && b.notifications.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _RecentNotifications(
                      notifications: b.notifications.take(3).toList(),
                      onSeeAll: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const NotificationsScreen()));
                        _refresh();
                      },
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _QuickActionsGrid(
                    onBrowseRfqs: () => _push(const BrowseRFQsScreen()),
                    onQuotations: () => _push(const MyQuotationsScreen()),
                    onOrders: () => _scrollToOrders(),
                    onWallet: () => _push(const WalletScreen()),
                    onMessages: () => _push(const ConversationsScreen()),
                    onTradeTools: () => _push(const TradeToolsScreen()),
                    onNegotiations: () => _push(const MyNegotiationsScreen()),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  sliver: SliverToBoxAdapter(
                    key: _ordersKey,
                    child: const _SectionHeader(icon: Icons.move_to_inbox_outlined, title: 'Incoming Orders'),
                  ),
                ),
                if (orders.isEmpty)
                  const SliverFillRemaining(
                      hasScrollBody: false, child: _ExporterEmptyState())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.builder(
                      itemCount: orders.length,
                      itemBuilder: (context, i) => _OrderCard(
                        order: orders[i],
                        index: i,
                        onAssignLogistics: () =>
                            _assignLogistics(orders[i]['id']),
                        onDocuments: () => _push(
                            OrderDocumentsScreen(orderId: orders[i]['id'])),
                        onDetails: () => _push(OrderDetailsScreen(
                            order: Order.fromJson(orders[i]))),
                      ),
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
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _assignLogistics(String orderId) async {
    final logisticsIdCtrl = TextEditingController();
    final trackingCtrl = TextEditingController();
    final carrierCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Assign 3PL Logistics'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: logisticsIdCtrl,
                  decoration: const InputDecoration(
                      labelText: "Logistics Partner's User ID")),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final picked = await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const BrowseLogisticsScreen()),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        logisticsIdCtrl.text = picked.userId;
                        carrierCtrl.text =
                            picked.companyName ?? picked.fullName;
                      });
                    }
                  },
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Find Logistics Partner'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: trackingCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Tracking Number')),
              const SizedBox(height: 10),
              TextField(
                  controller: carrierCtrl,
                  decoration: const InputDecoration(labelText: 'Carrier Name')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Assign')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    try {
      await _orderService.assignLogistics(
        orderId: orderId,
        logisticsId: logisticsIdCtrl.text.trim(),
        trackingNumber: trackingCtrl.text.trim(),
        carrierName: carrierCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Logistics assigned. Order marked as shipped.'),
              backgroundColor: AppColors.success),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
      }
    }
  }
}

/// Top-right avatar -> profile/company/documents/settings/logout menu, per the requested
/// "Profile Shortcut". Purely additive UI — all destinations are existing screens/actions.
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
      onSelected: (value) async {
        switch (value) {
          case 'profile':
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
            break;
          case 'company':
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
            break;
          case 'documents':
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const KYCScreen()));
            break;
          case 'catalog':
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ProductCatalogScreen()));
            break;
          case 'membership':
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MembershipScreen()));
            break;
          case 'ads':
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AdsScreen()));
            break;
          case 'disputes':
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DisputesScreen()));
            break;
          case 'logout':
            auth.logout();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
            value: 'profile',
            child: ListTile(
                leading: Icon(Icons.person_outline),
                title: Text('Profile'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'company',
            child: ListTile(
                leading: Icon(Icons.apartment_outlined),
                title: Text('Company'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'documents',
            child: ListTile(
                leading: Icon(Icons.description_outlined),
                title: Text('Documents / KYC'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'catalog',
            child: ListTile(
                leading: Icon(Icons.inventory_2_outlined),
                title: Text('My Catalog'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'membership',
            child: ListTile(
                leading: Icon(Icons.workspace_premium_outlined),
                title: Text('Membership'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'ads',
            child: ListTile(
                leading: Icon(Icons.campaign_outlined),
                title: Text('Advertisements'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'disputes',
            child: ListTile(
                leading: Icon(Icons.gavel_outlined),
                title: Text('My Disputes'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'logout',
            child: ListTile(
                leading: Icon(Icons.logout, color: AppColors.error),
                title: Text('Logout', style: TextStyle(color: AppColors.error)),
                contentPadding: EdgeInsets.zero)),
      ],
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.4)),
          child: CircleAvatar(
            radius: 15,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Shared premium building blocks (dashboard-local — presentation only).
// ============================================================================

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
          decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 15, color: AppColors.secondary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        ),
      ],
    );
  }
}

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
  final String? companyName;
  final String? country;
  final bool verified;
  final int completionPercent;
  final VoidCallback onCompleteProfile;
  const _WelcomeCard({
    required this.name,
    this.companyName,
    this.country,
    required this.verified,
    required this.completionPercent,
    required this.onCompleteProfile,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark
        ? [AppColorsDark.secondary, AppColorsDark.primary, AppColorsDark.primary]
        : [const Color(0xFF0F172A), const Color(0xFF184A8C), const Color(0xFF1857C4)];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: Transform.scale(scale: 0.98 + 0.02 * v, child: child))),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        padding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
                color: colors.first.withValues(alpha: 0.38),
                blurRadius: 24,
                offset: const Offset(0, 12))
          ],
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
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
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
                      Flexible(
                          child: Text(name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18.5,
                                  fontWeight: FontWeight.w800, letterSpacing: -0.3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      if (verified) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified,
                            color: Color(0xFF6FE3A5), size: 18),
                      ],
                    ],
                  ),
                  if (companyName != null && companyName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(companyName!,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  const SizedBox(height: 9),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (country != null && country!.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13,
                                color: Colors.white.withValues(alpha: 0.8)),
                            const SizedBox(width: 3),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(country!,
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: verified
                              ? const Color(0xFF6FE3A5).withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: verified ? const Color(0xFF6FE3A5).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.25), width: 1),
                        ),
                        child: Text(
                          verified
                              ? 'Verified Exporter'
                              : 'Verification Pending',
                          style: TextStyle(
                              color: verified
                                  ? const Color(0xFF6FE3A5)
                                  : Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700),
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
                          builder: (context, val, _) =>
                              CircularProgressIndicator(
                            value: val,
                            strokeWidth: 5,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.2),
                            valueColor:
                                const AlwaysStoppedAnimation(Color(0xFF6FE3A5)),
                          ),
                        ),
                        Text('$completionPercent%',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('Profile',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 9.5)),
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

class _QuickSummaryGrid extends StatelessWidget {
  final int openRfqs;
  final int myQuotations;
  final int orders;
  final double walletBalance;
  final double pendingPayments;
  final VoidCallback onOpenRfqs;
  final VoidCallback onQuotations;
  final VoidCallback onOrders;
  final VoidCallback onWallet;
  const _QuickSummaryGrid({
    required this.openRfqs,
    required this.myQuotations,
    required this.orders,
    required this.walletBalance,
    required this.pendingPayments,
    required this.onOpenRfqs,
    required this.onQuotations,
    required this.onOrders,
    required this.onWallet,
  });

  @override
  Widget build(BuildContext context) {
    final row1 = [
      ('Open RFQs', '$openRfqs', Icons.request_quote_outlined, AppColors.primary, onOpenRfqs),
      ('My Quotations', '$myQuotations', Icons.description_outlined, AppColors.secondary, onQuotations),
      ('Orders', '$orders', Icons.inventory_2_outlined, AppColors.accent, onOrders),
    ];
    final row2 = [
      ('Wallet Balance', '₹${walletBalance.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined, AppColors.success, onWallet),
      ('Pending Payments', '₹${pendingPayments.toStringAsFixed(0)}', Icons.hourglass_top_outlined, AppColors.warning, onWallet),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              for (int i = 0; i < row1.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _Reveal(index: i, child: _StatCard(label: row1[i].$1, value: row1[i].$2, icon: row1[i].$3, color: row1[i].$4, onTap: row1[i].$5)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (int i = 0; i < row2.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _Reveal(index: row1.length + i, child: _StatCard(label: row2[i].$1, value: row2[i].$2, icon: row2[i].$3, color: row2[i].$4, onTap: row2[i].$5)),
                ),
              ],
            ],
          ),
        ],
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
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      required this.onTap});

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
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 6))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: -0.3),
                  maxLines: 1),
            ),
            const SizedBox(height: 2),
            Text(label,
                style:
                    const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _RecentNotifications extends StatelessWidget {
  final List<dynamic> notifications;
  final VoidCallback onSeeAll;
  const _RecentNotifications(
      {required this.notifications, required this.onSeeAll});

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
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
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
                    decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.notifications_outlined, size: 14, color: AppColors.secondary),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                      child: Text('Recent Notifications',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14))),
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
                        decoration: BoxDecoration(
                            color: n['is_read'] == true
                                ? Colors.grey.shade300
                                : AppColors.secondary,
                            shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n['title'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(n['body'] ?? '',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
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
  final VoidCallback onBrowseRfqs;
  final VoidCallback onQuotations;
  final VoidCallback onOrders;
  final VoidCallback onWallet;
  final VoidCallback onMessages;
  final VoidCallback onTradeTools;
  final VoidCallback? onNegotiations;
  const _QuickActionsGrid({
    required this.onBrowseRfqs,
    required this.onQuotations,
    required this.onOrders,
    required this.onWallet,
    required this.onMessages,
    required this.onTradeTools,
    this.onNegotiations,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        Icons.request_quote_outlined,
        'Browse RFQs',
        onBrowseRfqs,
        AppColors.primary
      ),
      (
        Icons.description_outlined,
        'My Quotations',
        onQuotations,
        AppColors.secondary
      ),
      (Icons.inventory_2_outlined, 'Orders', onOrders, AppColors.accent),
      (
        Icons.account_balance_wallet_outlined,
        'Wallet',
        onWallet,
        AppColors.success
      ),
      (Icons.chat_bubble_outline, 'Messages', onMessages, AppColors.heldBlue),
      (
        Icons.travel_explore_outlined,
        'Trade Tools',
        onTradeTools,
        AppColors.warning
      ),
      if (onNegotiations != null)
        (
          Icons.handshake_outlined,
          'Negotiations',
          onNegotiations!,
          AppColors.secondary
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.bolt_outlined, title: 'Quick Actions'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
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
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final dynamic order;
  final int index;
  final VoidCallback onAssignLogistics;
  final VoidCallback onDocuments;
  final VoidCallback onDetails;
  const _OrderCard(
      {required this.order,
      required this.index,
      required this.onAssignLogistics,
      required this.onDocuments,
      required this.onDetails});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final status = o['status'] as String;
    final color = statusColor(status);
    return _Reveal(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6))
          ],
        ),
        child: _TapScale(
          borderRadius: BorderRadius.circular(20),
          onTap: onDetails,
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
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.inventory_2_outlined,
                          color: color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(o['product_name'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (![
                      'payment_released',
                      'refunded',
                      'cancelled',
                      'disputed'
                    ].contains(status))
                      IconButton(
                        icon:
                            const Icon(Icons.report_problem_outlined, size: 20),
                        tooltip: 'Raise Dispute',
                        onPressed: () =>
                            showRaiseDisputeDialog(context, o['id']),
                      ),
                    IconButton(
                        icon: const Icon(Icons.description_outlined, size: 20),
                        tooltip: 'View Documents',
                        onPressed: onDocuments),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatusBadge(status: status),
                    const Spacer(),
                    Text(
                        '${o['order_number']} · Qty ${o['quantity']} ${o['unit']}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          size: 16, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text('You will receive: ₹${o['exporter_payout_amount']}',
                          style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDetails,
                        style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        label: const Text('Track Shipment'),
                      ),
                    ),
                    if (status == 'payment_held' || status == 'accepted') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onAssignLogistics,
                          style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          icon: const Icon(Icons.local_shipping_outlined,
                              size: 16),
                          label: const Text('Assign Logistics'),
                        ),
                      ),
                    ],
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

class _ExporterEmptyState extends StatelessWidget {
  const _ExporterEmptyState();

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
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppColors.secondary.withValues(alpha: 0.14),
                      AppColors.secondary.withValues(alpha: 0.04)
                    ]),
                    shape: BoxShape.circle),
                child: const Icon(Icons.inbox_outlined,
                    size: 44, color: AppColors.secondary),
              ),
            ),
            const SizedBox(height: 18),
            const Text('No Incoming Orders Yet',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            const Text(
                'Orders from importers will show up here once they accept one of your quotations.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BrowseRFQsScreen())),
              icon: const Icon(Icons.request_quote_outlined, size: 18),
              label: const Text('Browse Open RFQs'),
            ),
          ],
        ),
      ),
    );
  }
}

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
        Row(children: const [
          Expanded(child: _ShimmerBox(76)),
          SizedBox(width: 10),
          Expanded(child: _ShimmerBox(76)),
          SizedBox(width: 10),
          Expanded(child: _ShimmerBox(76))
        ]),
        Row(children: const [
          Expanded(child: _ShimmerBox(76)),
          SizedBox(width: 10),
          Expanded(child: _ShimmerBox(76))
        ]),
        const _ShimmerBox(140),
        const _ShimmerBox(120),
      ],
    );
  }
}
