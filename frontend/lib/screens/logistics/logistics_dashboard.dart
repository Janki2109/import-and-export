import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/company_service.dart';
import '../../services/kyc_service.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';
import '../../services/trade_service.dart';
import '../../models/company.dart';
import '../../models/order.dart';
import '../../models/trade.dart';
import '../../widgets/status_badge.dart';
import '../chat/conversations_screen.dart';
import '../profile/profile_screen.dart';
import '../shared/ads_screen.dart';
import '../shared/kyc_screen.dart';
import '../shared/membership_screen.dart';
import '../shared/notifications_screen.dart';
import '../wallet/wallet_screen.dart';
import '../../widgets/theme_toggle_button.dart';
import 'fleet_screen.dart';
import 'pod_upload_screen.dart';

const _inProgressStatuses = [
  'picked_up', 'at_warehouse', 'customs_clearance', 'loaded', 'in_transit', 'arrived_at_destination', 'out_for_delivery',
];
const _pendingPickupStatuses = ['assigned', 'pending', 'pickup_scheduled'];

/// Logistics/3PL partner's home — status updates + POD upload are the core job (kept
/// exactly as before); redesigned to match the Exporter Dashboard's visual language
/// (gradient welcome card, stat grid, quick actions, recent activity, skeleton loading).
class LogisticsDashboard extends ConsumerStatefulWidget {
  const LogisticsDashboard({super.key});
  @override
  ConsumerState<LogisticsDashboard> createState() => _LogisticsDashboardState();
}

/// Earnings is the lifetime sum of credit ledger entries (real, from wallet.transactions) —
/// distinct from Wallet Balance (current withdrawable amount). There is no rating system
/// anywhere in the backend, so Average Rating is shown as "—" rather than a fabricated
/// number; Pending Payments reuses the same escrow-pending field every wallet already
/// exposes (it's always 0 for a logistics account today since escrow payouts only ever go
/// to exporters — an honest zero, not a fake figure).
class _DashboardBundle {
  final bool kycVerified;
  final String? country;
  final int completionPercent;
  final List<Shipment> shipments;
  final WalletSummary? wallet;
  final List<dynamic> notifications;
  const _DashboardBundle({
    required this.kycVerified,
    required this.country,
    required this.completionPercent,
    required this.shipments,
    required this.wallet,
    required this.notifications,
  });
}

class _LogisticsDashboardState extends ConsumerState<LogisticsDashboard> {
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
      _orderService.myShipments().catchError((_) => <Shipment>[]),
      _tradeService.getMyWallet().catchError((_) => WalletSummary(balance: 0, transactions: [])),
      _companyService.getMine().catchError((_) => null),
      _kycService.getMyStatus().catchError((_) => <String, dynamic>{}),
      _notificationService.list().catchError((_) => []),
    ]);

    final shipments = results[0] as List<Shipment>;
    final wallet = results[1] as WalletSummary?;
    final company = results[2] as Company?;
    final kyc = results[3] as Map<String, dynamic>;

    final companyDone = company != null;
    final kycStatus = kyc['status'] as String?;
    final kycSubmitted = kyc.isNotEmpty;
    final kycApproved = kycStatus == 'approved';
    final steps = [companyDone, kycSubmitted, kycApproved];
    final completion = ((steps.where((s) => s).length / steps.length) * 100).round();

    return _DashboardBundle(
      kycVerified: kycApproved,
      country: company?.country,
      completionPercent: completion,
      shipments: shipments,
      wallet: wallet,
      notifications: results[4] as List<dynamic>,
    );
  }

  Future<void> _captureDelivery(Shipment shipment) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PODUploadScreen(shipmentId: shipment.id)),
    );
    if (done == true) {
      await _updateStatus(shipment, 'delivered');
    }
  }

  Future<void> _updateStatus(Shipment shipment, String newStatus) async {
    try {
      await _orderService.updateShipmentStatus(shipmentId: shipment.id, status: newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated: ${statusLabel(newStatus)}'), backgroundColor: AppColors.success),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  final _shipmentsKey = GlobalKey();
  void _scrollToShipments() {
    final ctx = _shipmentsKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        // FittedBox scales the title down instead of truncating it, so the full
        // "Logistics Dashboard" text always stays visible even on narrow phones.
        title: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Logistics Dashboard')),
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
          _ProfileMenuButton(name: auth.currentUser?.fullName ?? 'Logistics Partner'),
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
            final shipments = b?.shipments ?? [];
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _WelcomeCard(
                    name: auth.currentUser?.fullName ?? 'Logistics Partner',
                    companyName: auth.currentUser?.companyName,
                    country: b?.country,
                    verified: b?.kycVerified ?? false,
                    completionPercent: b?.completionPercent ?? 0,
                    onCompleteProfile: () => _push(const KYCScreen()),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _StatsGrid(
                    shipments: shipments,
                    wallet: b?.wallet,
                    onShipments: _scrollToShipments,
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
                    onAssignedShipments: _scrollToShipments,
                    onPickupRequests: _scrollToShipments,
                    onDeliveryTracking: _scrollToShipments,
                    onEarnings: () => _push(const WalletScreen()),
                    onWallet: () => _push(const WalletScreen()),
                    onMessages: () => _push(const ConversationsScreen()),
                    onDocuments: () => _push(const KYCScreen()),
                    onProfile: () => _push(const ProfileScreen()),
                  ),
                ),
                if (shipments.isNotEmpty) SliverToBoxAdapter(child: _RecentActivity(shipments: shipments)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  sliver: SliverToBoxAdapter(
                    key: _shipmentsKey,
                    child: Text('Assigned Shipments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ),
                if (shipments.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: _LogisticsEmptyState())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.builder(
                      itemCount: shipments.length,
                      itemBuilder: (context, i) => _ShipmentCard(
                        index: i,
                        shipment: shipments[i],
                        onUpdateStatus: _updateStatus,
                        onCaptureDelivery: _captureDelivery,
                      ),
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

/// Top-right avatar -> profile/documents/settings/logout menu — same pattern as the
/// Exporter Dashboard's profile menu, logistics-relevant destinations.
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
          case 'fleet':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FleetScreen()));
            break;
          case 'membership':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MembershipScreen()));
            break;
          case 'ads':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdsScreen()));
            break;
          case 'logout':
            auth.logout();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profile'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'documents', child: ListTile(leading: Icon(Icons.description_outlined), title: Text('Documents / KYC'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'fleet', child: ListTile(leading: Icon(Icons.local_shipping_outlined), title: Text('My Fleet'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'membership', child: ListTile(leading: Icon(Icons.workspace_premium_outlined), title: Text('Membership'), contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'ads', child: ListTile(leading: Icon(Icons.campaign_outlined), title: Text('Advertisements'), contentPadding: EdgeInsets.zero)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout, color: AppColors.error), title: Text('Logout', style: TextStyle(color: AppColors.error)), contentPadding: EdgeInsets.zero)),
      ],
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// Welcome card — company name, country, verified badge, and profile completion ring.
/// Same layout/animation as the Exporter/Importer dashboards. Rating isn't shown here
/// (no rating system in the backend) — kept in the stats grid as an honest "—" instead.
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
        ? [AppColorsDark.primary, AppColorsDark.secondary]
        : [const Color(0xFF0B3D91), const Color(0xFF1857C4)];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child)),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        // LEFT: avatar. CENTER: Welcome Back / Name / Country / Verification badge (Expanded,
        // so it can never push the RIGHT completion circle out of the card). RIGHT: circular
        // profile-completion indicator, always right-aligned since it's a fixed-size, non-
        // flexible item after the Expanded center column.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Welcome Back', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (companyName != null && companyName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(companyName!, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  const SizedBox(height: 8),
                  // Wrap (not Row) — the verification badge automatically drops to its own
                  // line instead of overflowing when the country name is long or the card is
                  // narrow, and the country name itself is ellipsis-safe.
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
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: verified ? const Color(0xFF6FE3A5).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (verified) ...[
                              const Icon(Icons.verified, color: Color(0xFF6FE3A5), size: 12),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              verified ? 'Verified Partner' : 'Verification Pending',
                              style: TextStyle(color: verified ? const Color(0xFF6FE3A5) : Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: completionPercent < 100 ? onCompleteProfile : null,
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
                          duration: const Duration(milliseconds: 700),
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
          ],
        ),
      ),
    );
  }
}

/// 8-card, 2-column statistics grid — all figures derived from real, already-fetched data
/// (shipments list + wallet summary). Average Rating shows "—" honestly since no rating
/// system exists in the backend; Pending Payments is the same escrow-pending field every
/// wallet exposes (currently always 0 for logistics accounts — an honest zero).
class _StatsGrid extends StatelessWidget {
  final List<Shipment> shipments;
  final WalletSummary? wallet;
  final VoidCallback onShipments;
  final VoidCallback onWallet;
  const _StatsGrid({required this.shipments, required this.wallet, required this.onShipments, required this.onWallet});

  @override
  Widget build(BuildContext context) {
    final active = shipments.where((s) => _inProgressStatuses.contains(s.status)).length;
    final completed = shipments.where((s) => s.status == 'delivered').length;
    final pendingPickups = shipments.where((s) => _pendingPickupStatuses.contains(s.status)).length;
    final earnings = (wallet?.transactions ?? []).where((t) => t.entryType == 'credit').fold<double>(0, (sum, t) => sum + t.amount);
    final walletBalance = wallet?.balance ?? 0;
    final pendingPayments = wallet?.pendingRelease ?? 0;

    final items = [
      ('Assigned Shipments', '${shipments.length}', Icons.local_shipping_outlined, AppColors.primary, onShipments),
      ('Active Deliveries', '$active', Icons.route_outlined, AppColors.heldBlue, onShipments),
      ('Completed Deliveries', '$completed', Icons.task_alt_outlined, AppColors.success, onShipments),
      ('Pending Pickups', '$pendingPickups', Icons.event_available_outlined, AppColors.warning, onShipments),
      ('Earnings', '₹${earnings.toStringAsFixed(0)}', Icons.trending_up, Colors.purple, onWallet),
      ('Wallet Balance', '₹${walletBalance.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined, AppColors.success, onWallet),
      ('Average Rating', '—', Icons.star_outline, AppColors.accent, onShipments),
      ('Pending Payments', '₹${pendingPayments.toStringAsFixed(0)}', Icons.hourglass_top_outlined, AppColors.warning, onWallet),
    ];

    const crossAxisCount = 2;
    const spacing = 10.0;
    // Target a fixed card height (not one derived from a width-based aspect ratio) so cards
    // stay tall enough to fit icon + value + a 2-line label on narrow phones, instead of
    // shrinking (and overflowing) as the screen gets smaller.
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
            children: items.map((it) => _StatCard(label: it.$1, value: it.$2, icon: it.$3, color: it.$4, onTap: it.$5)).toList(),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(height: 8),
            // FittedBox scales the value down instead of overflowing/clipping for large
            // figures (e.g. big earnings/wallet amounts).
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5), maxLines: 1),
            ),
            const SizedBox(height: 4),
            // Expanded + maxLines:2 lets the label wrap to a second line and absorbs any
            // remaining card height, so it can never overflow the card.
            Expanded(
              child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5), maxLines: 2, overflow: TextOverflow.ellipsis),
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
                  const Icon(Icons.notifications_outlined, size: 17, color: AppColors.primary),
                  const SizedBox(width: 8),
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
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  final VoidCallback onAssignedShipments;
  final VoidCallback onPickupRequests;
  final VoidCallback onDeliveryTracking;
  final VoidCallback onEarnings;
  final VoidCallback onWallet;
  final VoidCallback onMessages;
  final VoidCallback onDocuments;
  final VoidCallback onProfile;
  const _QuickActionsGrid({
    required this.onAssignedShipments,
    required this.onPickupRequests,
    required this.onDeliveryTracking,
    required this.onEarnings,
    required this.onWallet,
    required this.onMessages,
    required this.onDocuments,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.local_shipping_outlined, 'Assigned\nShipments', onAssignedShipments, AppColors.primary),
      (Icons.event_available_outlined, 'Pickup\nRequests', onPickupRequests, AppColors.warning),
      (Icons.route_outlined, 'Delivery\nTracking', onDeliveryTracking, AppColors.heldBlue),
      (Icons.trending_up, 'Earnings', onEarnings, Colors.purple),
      (Icons.account_balance_wallet_outlined, 'Wallet', onWallet, AppColors.success),
      (Icons.chat_bubble_outline, 'Messages', onMessages, AppColors.accent),
      (Icons.description_outlined, 'Documents', onDocuments, AppColors.secondary),
      (Icons.person_outline, 'Profile', onProfile, AppColors.primary),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: items
                .map((it) => InkWell(
                      onTap: it.$3,
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
                              decoration: BoxDecoration(color: it.$4.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                              child: Icon(it.$1, color: it.$4, size: 19),
                            ),
                            const SizedBox(height: 8),
                            Text(it.$2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, height: 1.2)),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// Today's pickups + recent delivery/shipment status updates — real data only, capped to 4.
class _RecentActivity extends StatelessWidget {
  final List<Shipment> shipments;
  const _RecentActivity({required this.shipments});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todaysPickups = shipments.where((s) {
      final eta = s.estimatedDelivery;
      return _pendingPickupStatuses.contains(s.status) &&
          eta != null &&
          eta.year == now.year &&
          eta.month == now.month &&
          eta.day == now.day;
    }).toList();
    // Shipment has no updatedAt/createdAt field on the client model — keep the backend's
    // own ordering (myShipments() is already sorted newest-first server-side).
    final latestUpdates = shipments;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
            Text('Recent Activity', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (todaysPickups.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text("Today's Pickups", style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...todaysPickups.take(4).map((s) => _activityRow(icon: Icons.event_available_outlined, title: s.trackingNumber ?? s.id.substring(0, 8), status: s.status)),
            ],
            const SizedBox(height: 12),
            const Text('Shipment Updates', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...latestUpdates.take(4).map((s) => _activityRow(icon: Icons.local_shipping_outlined, title: s.trackingNumber ?? s.id.substring(0, 8), status: s.status)),
          ],
        ),
      ),
    );
  }

  Widget _activityRow({required IconData icon, required String title, required String status}) {
    final color = statusColor(status);
    return Padding(
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
  }
}

/// Shipment card — same status-progression action chips as before (business logic
/// untouched), restyled to match the Exporter/Importer dashboard card language.
class _ShipmentCard extends StatelessWidget {
  final int index;
  final Shipment shipment;
  final void Function(Shipment, String) onUpdateStatus;
  final void Function(Shipment) onCaptureDelivery;
  const _ShipmentCard({required this.index, required this.shipment, required this.onUpdateStatus, required this.onCaptureDelivery});

  @override
  Widget build(BuildContext context) {
    final s = shipment;
    final color = statusColor(s.status);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (index * 25).clamp(0, 250)),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: child)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 5))],
        ),
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
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.local_shipping_outlined, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(s.trackingNumber ?? s.id.substring(0, 8), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  StatusBadge(status: s.status),
                ],
              ),
              if (s.carrierName != null) ...[
                const SizedBox(height: 8),
                Text(s.carrierName!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              ],
              if (s.pickupAddress != null) ...[
                const SizedBox(height: 6),
                _addressRow(Icons.trip_origin, 'Pickup', s.pickupAddress!),
              ],
              if (s.deliveryAddress != null) ...[
                const SizedBox(height: 4),
                _addressRow(Icons.location_on_outlined, 'Delivery', s.deliveryAddress!),
              ],
              if (s.estimatedDelivery != null) ...[
                const SizedBox(height: 4),
                Text('ETA: ${s.estimatedDelivery!.day}/${s.estimatedDelivery!.month}/${s.estimatedDelivery!.year}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (s.status == 'assigned')
                    _actionChip('Pickup Scheduled', Icons.event_available_outlined, () => onUpdateStatus(s, 'pickup_scheduled')),
                  if (s.status == 'pickup_scheduled')
                    _actionChip('Goods Picked Up', Icons.inventory_2_outlined, () => onUpdateStatus(s, 'picked_up')),
                  if (s.status == 'picked_up')
                    _actionChip('At Warehouse', Icons.warehouse_outlined, () => onUpdateStatus(s, 'at_warehouse')),
                  if (s.status == 'at_warehouse')
                    _actionChip('Customs Clearance', Icons.gavel_outlined, () => onUpdateStatus(s, 'customs_clearance')),
                  if (s.status == 'customs_clearance')
                    _actionChip('Loaded on Ship/Flight', Icons.flight_takeoff_outlined, () => onUpdateStatus(s, 'loaded')),
                  if (s.status == 'loaded')
                    _actionChip('In Transit', Icons.local_shipping_outlined, () => onUpdateStatus(s, 'in_transit')),
                  if (s.status == 'in_transit')
                    _actionChip('Arrived at Destination', Icons.anchor_outlined, () => onUpdateStatus(s, 'arrived_at_destination')),
                  if (s.status == 'arrived_at_destination')
                    _actionChip('Out for Delivery', Icons.delivery_dining_outlined, () => onUpdateStatus(s, 'out_for_delivery')),
                  if (s.status == 'out_for_delivery')
                    _actionChip('Delivered', Icons.check_circle_outline, () => onCaptureDelivery(s), color: AppColors.success),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addressRow(IconData icon, String label, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text('$label: $address', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _actionChip(String label, IconData icon, VoidCallback onTap, {Color? color}) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color ?? AppColors.primary),
      label: Text(label, style: TextStyle(color: color ?? AppColors.primary, fontWeight: FontWeight.w600)),
      backgroundColor: (color ?? AppColors.primary).withValues(alpha: 0.08),
      onPressed: onTap,
    );
  }
}

/// Professional empty state — matches the spec's exact copy.
class _LogisticsEmptyState extends StatelessWidget {
  const _LogisticsEmptyState();

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
              decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.14), AppColors.primary.withValues(alpha: 0.04)]), shape: BoxShape.circle),
              child: const Icon(Icons.local_shipping_outlined, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text('No Shipments Assigned', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            const Text('You will see shipments here after an admin assigns them.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w}) => Container(
          width: w,
          height: h,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(18)),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        box(120),
        Row(children: [Expanded(child: box(76)), const SizedBox(width: 10), Expanded(child: box(76))]),
        Row(children: [Expanded(child: box(76)), const SizedBox(width: 10), Expanded(child: box(76))]),
        box(140),
        box(120),
      ],
    );
  }
}
