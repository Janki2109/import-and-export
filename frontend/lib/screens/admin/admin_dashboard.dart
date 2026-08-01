import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_client.dart';
import '../../models/admin.dart';
import '../../providers/providers.dart';
import '../../services/admin_service.dart';
import '../../widgets/theme_toggle_button.dart';
import '../chat/conversations_screen.dart';
import '../profile/profile_screen.dart';
import 'admin_audit_log_screen.dart';
import 'admin_chat_screen.dart';
import 'admin_compliance_screen.dart';
import 'admin_disputes_screen.dart';
import 'admin_escrow_screen.dart';
import 'admin_fraud_screen.dart';
import 'admin_kyc_review_screen.dart';
import 'admin_logistics_screen.dart';
import 'admin_negotiation_screen.dart';
import 'admin_notification_screen.dart';
import 'admin_payment_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_quotation_screen.dart';
import 'admin_reference_data_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_rfq_screen.dart';
import 'admin_search_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_shipment_screen.dart';
import 'admin_users_screen.dart';
import 'admin_wallet_screen.dart';
import 'admin_withdrawal_screen.dart';

enum _Section {
  dashboard,
  users,
  kyc,
  rfqs,
  quotations,
  orders,
  escrow,
  wallets,
  withdrawals,
  shipments,
  logistics,
  chats,
  compliance,
  negotiations,
  payments,
  disputes,
  fraud,
  tradeTools,
  reports,
  notifications,
  auditLogs,
  settings,
  messages,
  profile,
}

/// Admin Panel shell — persistent sidebar (rail on narrow screens, full drawer-style rail on
/// wide) hosting the dashboard plus every admin management screen.
class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});
  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _NavItem {
  final String label;
  final IconData icon;
  final _Section section;
  const _NavItem(this.label, this.icon, this.section);
}

const _navItems = [
  _NavItem('Dashboard', Icons.dashboard_outlined, _Section.dashboard),
  _NavItem('Users', Icons.people_outline, _Section.users),
  _NavItem('KYC Review', Icons.verified_user_outlined, _Section.kyc),
  _NavItem('RFQs', Icons.request_quote_outlined, _Section.rfqs),
  _NavItem('Quotations', Icons.description_outlined, _Section.quotations),
  _NavItem('Orders', Icons.receipt_long_outlined, _Section.orders),
  _NavItem('Escrow', Icons.account_balance_wallet_outlined, _Section.escrow),
  _NavItem('Wallets', Icons.savings_outlined, _Section.wallets),
  _NavItem('Withdrawals', Icons.request_page_outlined, _Section.withdrawals),
  _NavItem('Shipments', Icons.local_shipping_outlined, _Section.shipments),
  _NavItem('Logistics', Icons.local_shipping_outlined, _Section.logistics),
  _NavItem('Chats', Icons.forum_outlined, _Section.chats),
  _NavItem('Compliance Center', Icons.fact_check_outlined, _Section.compliance),
  _NavItem('Negotiation Center', Icons.handshake_outlined, _Section.negotiations),
  _NavItem('Payment Management', Icons.account_balance_wallet_outlined, _Section.payments),
  _NavItem('Disputes', Icons.report_problem_outlined, _Section.disputes),
  _NavItem('Fraud Signals', Icons.security_outlined, _Section.fraud),
  _NavItem('Trade Tools', Icons.public_outlined, _Section.tradeTools),
  _NavItem('Reports', Icons.bar_chart_outlined, _Section.reports),
  _NavItem('Notifications', Icons.campaign_outlined, _Section.notifications),
  _NavItem('Audit Logs', Icons.history_outlined, _Section.auditLogs),
  _NavItem('Settings', Icons.settings_outlined, _Section.settings),
];

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  _Section _active = _Section.dashboard;

  void _select(_NavItem item) => setState(() => _active = item.section);

  Widget _body() {
    switch (_active) {
      case _Section.dashboard:
        return const _AdminDashboardHome();
      case _Section.users:
        return const AdminUsersScreen();
      case _Section.kyc:
        return const AdminKYCReviewScreen();
      case _Section.rfqs:
        return const AdminRFQScreen();
      case _Section.quotations:
        return const AdminQuotationScreen();
      case _Section.orders:
        return const AdminOrdersScreen();
      case _Section.escrow:
        return const AdminEscrowScreen();
      case _Section.wallets:
        return const AdminWalletScreen();
      case _Section.withdrawals:
        return const AdminWithdrawalScreen();
      case _Section.shipments:
        return const AdminShipmentScreen();
      case _Section.logistics:
        return const AdminLogisticsScreen();
      case _Section.chats:
        return const AdminChatScreen();
      case _Section.compliance:
        return const AdminComplianceScreen();
      case _Section.negotiations:
        return const AdminNegotiationScreen();
      case _Section.payments:
        return const AdminPaymentScreen();
      case _Section.disputes:
        return const AdminDisputesScreen();
      case _Section.fraud:
        return const AdminFraudScreen();
      case _Section.tradeTools:
        return const AdminReferenceDataScreen();
      case _Section.reports:
        return const AdminReportsScreen();
      case _Section.notifications:
        return const AdminNotificationScreen();
      case _Section.auditLogs:
        return const AdminAuditLogScreen();
      case _Section.settings:
        return const AdminSettingsScreen();
      case _Section.messages:
        return const ConversationsScreen();
      case _Section.profile:
        return const ProfileScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final wide = MediaQuery.of(context).size.width >= 900;

    final sidebar = _Sidebar(
      active: _active,
      name: auth.currentUser?.fullName ?? 'Admin',
      onSelect: _select,
      onLogout: () => auth.logout(),
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            sidebar,
            Expanded(
              child: Column(
                children: [
                  _TopBar(auth: auth, wide: true),
                  Expanded(child: _body()),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        // FittedBox scales the title down instead of truncating it, so the full "Admin
        // Panel" text always stays visible even on narrow phones with several action icons.
        title: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Admin Panel')),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Global Search',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminSearchScreen())),
          ),
          const ThemeToggleButton(),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => auth.logout()),
        ],
      ),
      drawer: Drawer(child: sidebar),
      body: _body(),
    );
  }
}

class _TopBar extends StatelessWidget {
  final dynamic auth;
  final bool wide;
  const _TopBar({required this.auth, required this.wide});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Row(
        children: [
          const Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Global Search',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminSearchScreen())),
          ),
          const ThemeToggleButton(),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text((auth.currentUser?.fullName ?? 'A').substring(0, 1).toUpperCase(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          // Flexible so a long admin name shrinks-to-ellipsis instead of overflowing past
          // the top bar's right edge — the name is the last, unbounded item in this Row.
          Flexible(
            child: Text(auth.currentUser?.fullName ?? 'Admin', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final _Section active;
  final String name;
  final ValueChanged<_NavItem> onSelect;
  final VoidCallback onLogout;
  const _Sidebar({required this.active, required this.name, required this.onSelect, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: Theme.of(context).cardTheme.color,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)]), borderRadius: BorderRadius.circular(11)),
                    child: const Icon(Icons.shield_outlined, color: Colors.white, size: 19),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _navItems.map((item) {
                  final selected = item.section == active;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    child: Material(
                      color: selected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: Icon(item.icon, size: 19, color: selected ? AppColors.primary : AppColors.textSecondary),
                        title: Text(item.label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppColors.primary : null)),
                        onTap: () => onSelect(item),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_outline, size: 19, color: AppColors.textSecondary),
              title: const Text('Profile', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              onTap: () => onSelect(const _NavItem('Profile', Icons.person_outline, _Section.profile)),
            ),
            ListTile(
              leading: const Icon(Icons.logout, size: 19, color: AppColors.error),
              title: const Text('Logout', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.error)),
              onTap: onLogout,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Premium dashboard home — stat cards, charts, recent activity, and quick actions. All data
/// comes from the existing Analytics/EscrowSummary endpoints plus the new chart-analytics
/// endpoint added for this screen.
class _AdminDashboardHome extends StatefulWidget {
  const _AdminDashboardHome();
  @override
  State<_AdminDashboardHome> createState() => _AdminDashboardHomeState();
}

class _DashboardData {
  final Analytics analytics;
  final EscrowSummary escrow;
  final ChartAnalytics charts;
  final List<dynamic> recentOrders;
  const _DashboardData({required this.analytics, required this.escrow, required this.charts, required this.recentOrders});
}

class _AdminDashboardHomeState extends State<_AdminDashboardHome> {
  final _service = AdminService();
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final results = await Future.wait([
      _service.getAnalytics(),
      _service.getEscrowSummary(),
      _service.getChartAnalytics(),
      ApiClient().get('/admin/orders').then((r) => (r.data['data'] as List? ?? [])).catchError((_) => []),
    ]);
    return _DashboardData(
      analytics: results[0] as Analytics,
      escrow: results[1] as EscrowSummary,
      charts: results[2] as ChartAnalytics,
      recentOrders: (results[3] as List).take(5).toList(),
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _DashboardSkeleton();
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
          }
          final d = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatGrid(analytics: d.analytics, escrow: d.escrow, charts: d.charts),
              const SizedBox(height: 20),
              Text('Charts & Trends', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final twoCol = constraints.maxWidth >= 720;
                final charts = [
                  _ChartCard(title: 'Monthly Orders', child: _BarChart(points: d.charts.monthlyOrders, color: AppColors.primary)),
                  _ChartCard(title: 'Monthly Revenue', child: _LineChartView(points: d.charts.monthlyRevenue, color: AppColors.success)),
                  _ChartCard(title: 'Country-wise Trade (RFQs)', child: _PieChartView(items: d.charts.countryTrade)),
                  _ChartCard(title: 'RFQ Trend', child: _LineChartView(points: d.charts.rfqTrend, color: AppColors.accent)),
                  _ChartCard(title: 'Top Export Categories', child: _HorizontalBarList(items: d.charts.topExportCategories)),
                ];
                if (!twoCol) return Column(children: charts.map((c) => Padding(padding: const EdgeInsets.only(bottom: 14), child: c)).toList());
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: charts.map((c) => SizedBox(width: (constraints.maxWidth - 14) / 2, child: c)).toList(),
                );
              }),
              const SizedBox(height: 20),
              Text('Recent Orders', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (d.recentOrders.isEmpty)
                const Text('No orders yet.', style: TextStyle(color: AppColors.textSecondary))
              else
                ...d.recentOrders.map((o) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]),
                      child: Row(
                        children: [
                          Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.receipt_long_outlined, color: AppColors.primary, size: 18)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o['order_number'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                Text(o['product_name'] ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          Text('₹${o['total_amount']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    )),
              const SizedBox(height: 20),
              Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _QuickActionsGrid(),
            ],
          );
        },
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final Analytics analytics;
  final EscrowSummary escrow;
  final ChartAnalytics charts;
  const _StatGrid({required this.analytics, required this.escrow, required this.charts});

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('Total Importers', '${analytics.totalImporters}', Icons.storefront_outlined, AppColors.primary),
      ('Total Exporters', '${analytics.totalExporters}', Icons.local_shipping_outlined, AppColors.secondary),
      ('Total Logistics', '${analytics.totalLogistics}', Icons.local_shipping_outlined, AppColors.accent),
      ('Total Orders', '${analytics.totalOrders}', Icons.receipt_long_outlined, AppColors.heldBlue),
      ('Open RFQs', '${charts.openRfqCount}', Icons.request_quote_outlined, AppColors.warning),
      ('Active Shipments', '${charts.activeShipmentCount}', Icons.local_shipping_outlined, AppColors.primary),
      ('Escrow Balance', '₹${escrow.holdingBalance.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined, AppColors.heldBlue),
      ('Released Payments', '₹${escrow.totalReleased.toStringAsFixed(0)}', Icons.check_circle_outline, AppColors.success),
      ('Wallet Transactions', '${charts.walletTxnCount}', Icons.savings_outlined, AppColors.secondary),
      ('Revenue', '₹${analytics.totalPlatformFees.toStringAsFixed(0)}', Icons.trending_up, AppColors.success),
    ];
    // Target a fixed card height (not one derived from a width-based aspect ratio) so cards
    // stay tall enough to fit icon + value + a 2-line label on narrow phones, instead of
    // shrinking (and overflowing) as the screen gets smaller or more columns are packed in.
    const targetCardHeight = 128.0;
    const spacing = 12.0;
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth >= 900 ? 5 : (constraints.maxWidth >= 600 ? 3 : 2);
      final cellWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
      final aspectRatio = cellWidth / targetCardHeight;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: aspectRatio,
        children: stats
            .map((s) => Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Container(width: 30, height: 30, decoration: BoxDecoration(color: s.$4.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)), child: Icon(s.$3, size: 15, color: s.$4)),
                      const SizedBox(height: 8),
                      // FittedBox scales large values (e.g. big revenue/escrow figures)
                      // down instead of overflowing/clipping.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 1),
                      ),
                      const SizedBox(height: 4),
                      // Expanded + maxLines:2 lets the label wrap to a second line and
                      // absorbs remaining card height, so it can never overflow the card.
                      Expanded(
                        child: Text(s.$1, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ))
            .toList(),
      );
    });
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: 240,
      decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<MonthPoint> points;
  final Color color;
  const _BarChart({required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const Center(child: Text('No data yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)));
    final maxY = (points.map((p) => p.count).fold<int>(0, (a, b) => a > b ? a : b)).toDouble();
    return BarChart(BarChartData(
      maxY: maxY <= 0 ? 1 : maxY * 1.2,
      barTouchData: BarTouchData(enabled: true),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) {
          final i = v.toInt();
          if (i < 0 || i >= points.length) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(top: 6), child: Text(points[i].month.split(' ').first, style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary)));
        })),
      ),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      barGroups: [
        for (int i = 0; i < points.length; i++)
          BarChartGroupData(x: i, barRods: [BarChartRodData(toY: points[i].count.toDouble(), color: color, width: 16, borderRadius: BorderRadius.circular(6))]),
      ],
    ));
  }
}

class _LineChartView extends StatelessWidget {
  final List<MonthPoint> points;
  final Color color;
  const _LineChartView({required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const Center(child: Text('No data yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)));
    final useValue = points.any((p) => p.value > 0);
    final spots = [for (int i = 0; i < points.length; i++) FlSpot(i.toDouble(), useValue ? points[i].value : points[i].count.toDouble())];
    return LineChart(LineChartData(
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) {
          final i = v.toInt();
          if (i < 0 || i >= points.length) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(top: 6), child: Text(points[i].month.split(' ').first, style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary)));
        })),
      ),
      lineBarsData: [
        LineChartBarData(spots: spots, isCurved: true, color: color, barWidth: 3, dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12))),
      ],
    ));
  }
}

class _PieChartView extends StatelessWidget {
  final List<NamedCount> items;
  const _PieChartView({required this.items});

  static const _palette = [AppColors.primary, AppColors.secondary, AppColors.accent, AppColors.heldBlue, AppColors.warning, AppColors.success, Colors.purple, Colors.teal];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('No data yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)));
    final total = items.fold<int>(0, (a, b) => a + b.count);
    return Row(
      children: [
        Expanded(
          child: PieChart(PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 30,
            sections: [
              for (int i = 0; i < items.length; i++)
                PieChartSectionData(value: items[i].count.toDouble(), color: _palette[i % _palette.length], title: '', radius: 40),
            ],
          )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final pct = total > 0 ? (items[i].count / total * 100).toStringAsFixed(0) : '0';
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(items[i].label, style: const TextStyle(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('$pct%', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HorizontalBarList extends StatelessWidget {
  final List<NamedCount> items;
  const _HorizontalBarList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('No data yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)));
    final maxCount = items.map((e) => e.count).fold<int>(0, (a, b) => a > b ? a : b);
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final ratio = maxCount > 0 ? items[i].count / maxCount : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(items[i].label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('${items[i].count}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: ratio, minHeight: 6, backgroundColor: Colors.grey.shade200, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickActionsGrid extends StatefulWidget {
  @override
  State<_QuickActionsGrid> createState() => _QuickActionsGridState();
}

class _QuickActionsGridState extends State<_QuickActionsGrid> {
  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_AdminDashboardState>();
    final items = [
      ('Manage Users', Icons.people_outline, _Section.users),
      ('Manage Orders', Icons.receipt_long_outlined, _Section.orders),
      ('Manage Escrow', Icons.account_balance_wallet_outlined, _Section.escrow),
      ('Manage Shipments', Icons.local_shipping_outlined, _Section.shipments),
      ('Audit Logs', Icons.history_outlined, _Section.auditLogs),
      ('Fraud Signals', Icons.security_outlined, _Section.fraud),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.1,
      children: items
          .map((it) => InkWell(
                onTap: () => state?._select(_NavItem(it.$1, it.$2, it.$3)),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))]),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(it.$2, color: AppColors.primary, size: 22),
                      const SizedBox(height: 6),
                      Text(it.$1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h) => Container(height: h, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(18)));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [Expanded(child: box(76)), const SizedBox(width: 10), Expanded(child: box(76)), const SizedBox(width: 10), Expanded(child: box(76))]),
        box(240),
        box(240),
      ],
    );
  }
}
