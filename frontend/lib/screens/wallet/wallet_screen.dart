import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_theme.dart';
import '../../models/trade.dart';
import '../../providers/providers.dart';
import '../../services/trade_service.dart';
import '../../services/wallet_statement_export.dart';
import '../../services/wallet_transaction_helpers.dart';
import 'transaction_detail_screen.dart';
import 'withdraw_screen.dart';

enum _DateRangeFilter { all, today, thisWeek, thisMonth, custom }

/// Wallet — available balance + ledger transaction history. Shared across
/// exporter/logistics (who receive payouts) and importer (who can see fees/debits).
/// Data source is still TradeService.getMyWallet()/withdraw() — every summary figure,
/// filter, and status below is computed client-side from that same real ledger list.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});
  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  final _tradeService = TradeService();
  late Future<WalletSummary> _future;

  final _searchCtrl = TextEditingController();
  String _query = '';
  _DateRangeFilter _dateFilter = _DateRangeFilter.all;
  DateTimeRange? _customRange;
  String? _directionFilter; // 'credit' (Received) | 'debit' (Sent) | null (All)
  String? _statusFilter; // 'Completed' | 'Pending' | 'Refunded'
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _future = _tradeService.getMyWallet();
  }

  void _refresh() => setState(() => _future = _tradeService.getMyWallet());

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _withdraw(double maxAmount) async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => WithdrawScreen(availableBalance: maxAmount)));
    if (done == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Withdrawal initiated to your linked bank account.'), backgroundColor: AppColors.success));
        _refresh();
      }
    }
  }

  List<LedgerEntry> _applyFilters(List<LedgerEntry> txns) {
    var list = txns.where((t) {
      if (_query.trim().isNotEmpty && !t.description.toLowerCase().contains(_query.trim().toLowerCase())) return false;
      if (_directionFilter != null && t.entryType != _directionFilter) return false;
      if (_statusFilter != null && txnStatusLabel(t) != _statusFilter) return false;

      final now = DateTime.now();
      final d = t.createdAt.toLocal();
      switch (_dateFilter) {
        case _DateRangeFilter.all:
          return true;
        case _DateRangeFilter.today:
          return d.year == now.year && d.month == now.month && d.day == now.day;
        case _DateRangeFilter.thisWeek:
          return now.difference(d).inDays < 7;
        case _DateRangeFilter.thisMonth:
          return d.year == now.year && d.month == now.month;
        case _DateRangeFilter.custom:
          if (_customRange == null) return true;
          return !d.isBefore(_customRange!.start) && !d.isAfter(_customRange!.end.add(const Duration(days: 1)));
      }
    }).toList();
    return list;
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (range != null && mounted) setState(() { _customRange = range; _dateFilter = _DateRangeFilter.custom; });
  }

  Future<void> _downloadStatement(List<LedgerEntry> transactions, double balance) async {
    final format = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Download Statement', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            ListTile(leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.error), title: const Text('PDF'), onTap: () => Navigator.pop(ctx, 'pdf')),
            ListTile(leading: const Icon(Icons.table_chart_outlined, color: AppColors.success), title: const Text('Excel / CSV'), onTap: () => Navigator.pop(ctx, 'csv')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (format == null || !mounted) return;

    setState(() => _exporting = true);
    try {
      final auth = ref.read(authProvider);
      if (format == 'pdf') {
        final bytes = await buildWalletStatementPdf(balance: balance, transactions: transactions, accountName: auth.currentUser?.fullName ?? '');
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'wallet-statement.pdf');
      } else {
        final csv = buildWalletStatementCsv(transactions);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/wallet-statement.csv');
        await file.writeAsString(csv);
        await Share.shareXFiles([XFile(file.path)], text: 'Wallet Statement');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not export statement: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showWalletGuide() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Wallet Guide', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 12),
              _guideStep(Icons.account_balance_wallet_outlined, 'Earnings land here', 'When an order is delivered and escrow is released, your share is credited to this wallet.'),
              _guideStep(Icons.account_balance_outlined, 'Withdraw anytime', 'Move your balance to your linked bank account — processed manually by our team, usually within 1–3 business days.'),
              _guideStep(Icons.receipt_long_outlined, 'Track every transaction', 'Every credit, debit, and withdrawal is logged with a receipt you can download or share.'),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideStep(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.primary, size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction History')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<WalletSummary>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingSkeleton();
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final wallet = snapshot.data!;
            final filtered = _applyFilters(wallet.transactions);

            final totalReceived = wallet.transactions.where((t) => t.entryType == 'credit').fold<double>(0, (s, t) => s + t.amount);
            final totalSent = wallet.transactions.where((t) => t.entryType == 'debit').fold<double>(0, (s, t) => s + t.amount);
            final pendingWithdrawal = wallet.transactions.where((t) => classifyTxn(t) == TxnKind.withdrawal && isTxnPending(t)).fold<double>(0, (s, t) => s + t.amount);
            final now = DateTime.now();
            final thisMonthEarnings = wallet.transactions.where((t) => t.entryType == 'credit' && t.createdAt.year == now.year && t.createdAt.month == now.month).fold<double>(0, (s, t) => s + t.amount);
            final lastUpdated = wallet.transactions.isNotEmpty ? wallet.transactions.first.createdAt : null;

            return Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _WalletHeaderCard(
                          balance: wallet.balance,
                          walletId: auth.currentUser?.id ?? '',
                          lastUpdated: lastUpdated,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _QuickActions(
                          onWithdraw: wallet.balance > 0 ? () => _withdraw(wallet.balance) : null,
                          onHistory: null, // history is already the body of this screen; disabled to avoid a no-op tap
                          onBankDetails: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Bank details are managed during KYC approval — contact support to update them.')),
                          ),
                          onStatement: _exporting ? null : () => _downloadStatement(filtered, wallet.balance),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _SummaryGrid(
                          totalReceived: totalReceived,
                          totalSent: totalSent,
                          pendingWithdrawal: pendingWithdrawal,
                          thisMonthEarnings: thisMonthEarnings,
                        ),
                      ),
                      if (wallet.pendingRelease > 0 || wallet.totalReleased > 0)
                        SliverToBoxAdapter(
                          child: _EscrowStrip(pendingRelease: wallet.pendingRelease, totalReleased: wallet.totalReleased),
                        ),
                      SliverToBoxAdapter(
                        child: _FiltersBar(
                          searchCtrl: _searchCtrl,
                          onSearchChanged: (v) => setState(() => _query = v),
                          dateFilter: _dateFilter,
                          onDateFilterChanged: (f) {
                            if (f == _DateRangeFilter.custom) {
                              _pickCustomRange();
                            } else {
                              setState(() => _dateFilter = f);
                            }
                          },
                          directionFilter: _directionFilter,
                          onDirectionFilterChanged: (t) => setState(() => _directionFilter = t),
                          statusFilter: _statusFilter,
                          onStatusFilterChanged: (s) => setState(() => _statusFilter = s),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        sliver: SliverToBoxAdapter(
                          child: Text('Transactions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      if (filtered.isEmpty)
                        SliverToBoxAdapter(child: _EmptyState(hasAnyTransactions: wallet.transactions.isNotEmpty, onGuideTap: _showWalletGuide))
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          sliver: SliverList.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) => _TransactionCard(
                              transaction: filtered[i],
                              index: i,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: filtered[i]))),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _BottomBar(
                  busy: _exporting,
                  canWithdraw: wallet.balance > 0,
                  onWithdraw: () => _withdraw(wallet.balance),
                  onRefresh: _refresh,
                  onStatement: () => _downloadStatement(filtered, wallet.balance),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Premium gradient wallet card with an animated balance counter.
class _WalletHeaderCard extends StatelessWidget {
  final double balance;
  final String walletId;
  final DateTime? lastUpdated;
  const _WalletHeaderCard({required this.balance, required this.walletId, this.lastUpdated});

  @override
  Widget build(BuildContext context) {
    final shortId = walletId.length > 8 ? walletId.substring(0, 8).toUpperCase() : walletId.toUpperCase();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: Icon(Icons.account_balance_wallet_outlined, size: 90, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Available Balance', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: balance),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, v, child) => Text('₹${v.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Wallet ID', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 9.5)),
                          Text(shortId, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 9.5)),
                          Row(children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            const Text('Active', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                lastUpdated != null ? 'Last updated: ${_relativeTime(lastUpdated!)}' : 'No transactions yet',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback? onWithdraw;
  final VoidCallback? onHistory;
  final VoidCallback onBankDetails;
  final VoidCallback? onStatement;
  const _QuickActions({required this.onWithdraw, required this.onHistory, required this.onBankDetails, required this.onStatement});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(child: _action(Icons.account_balance_outlined, 'Withdraw', onWithdraw)),
          const SizedBox(width: 10),
          Expanded(child: _action(Icons.history, 'History', onHistory)),
          const SizedBox(width: 10),
          Expanded(child: _action(Icons.badge_outlined, 'Bank Details', onBankDetails)),
          const SizedBox(width: 10),
          Expanded(child: _action(Icons.file_download_outlined, 'Statement', onStatement)),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4))]),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Real escrow figures from the backend (as opposed to the heuristic client-side summary
/// grid above) — only shown when relevant, i.e. for exporters who have orders with money
/// moving through escrow. Pending Release = held on the platform's escrow, not yet
/// released; Released via Escrow = lifetime payouts that have landed in this wallet.
class _EscrowStrip extends StatelessWidget {
  final double pendingRelease;
  final double totalReleased;
  const _EscrowStrip({required this.pendingRelease, required this.totalReleased});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary.withValues(alpha: 0.15))),
        child: Row(
          children: [
            Expanded(child: _figure('Pending Release', pendingRelease, Icons.hourglass_top_outlined, AppColors.warning)),
            Container(width: 1, height: 32, color: Colors.grey.shade300),
            Expanded(child: _figure('Released via Escrow', totalReleased, Icons.check_circle_outline, AppColors.success)),
          ],
        ),
      ),
    );
  }

  Widget _figure(String label, double value, IconData icon, Color color) {
    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 13, color: color), const SizedBox(width: 5), Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5))]),
        const SizedBox(height: 4),
        Text('₹${value.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color)),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final double totalReceived;
  final double totalSent;
  final double pendingWithdrawal;
  final double thisMonthEarnings;
  const _SummaryGrid({required this.totalReceived, required this.totalSent, required this.pendingWithdrawal, required this.thisMonthEarnings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.1,
        children: [
          _card('Total Received', totalReceived, Icons.arrow_downward, AppColors.success),
          _card('Total Sent', totalSent, Icons.arrow_upward, AppColors.error),
          _card('Pending Withdrawal', pendingWithdrawal, Icons.hourglass_top_outlined, AppColors.warning),
          _card('This Month Earnings', thisMonthEarnings, Icons.trending_up, AppColors.primary),
        ],
      ),
    );
  }

  Widget _card(String label, double value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 15, color: color), const SizedBox(width: 6), Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis))]),
            const Spacer(),
            Text('₹${value.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
          ],
        ),
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final _DateRangeFilter dateFilter;
  final ValueChanged<_DateRangeFilter> onDateFilterChanged;
  final String? directionFilter;
  final ValueChanged<String?> onDirectionFilterChanged;
  final String? statusFilter;
  final ValueChanged<String?> onStatusFilterChanged;

  const _FiltersBar({
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.dateFilter,
    required this.onDateFilterChanged,
    required this.directionFilter,
    required this.onDirectionFilterChanged,
    required this.statusFilter,
    required this.onStatusFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: searchCtrl,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(hintText: 'Search transactions', prefixIcon: Icon(Icons.search)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip('All Dates', dateFilter == _DateRangeFilter.all, () => onDateFilterChanged(_DateRangeFilter.all)),
                const SizedBox(width: 6),
                _chip('Today', dateFilter == _DateRangeFilter.today, () => onDateFilterChanged(_DateRangeFilter.today)),
                const SizedBox(width: 6),
                _chip('This Week', dateFilter == _DateRangeFilter.thisWeek, () => onDateFilterChanged(_DateRangeFilter.thisWeek)),
                const SizedBox(width: 6),
                _chip('This Month', dateFilter == _DateRangeFilter.thisMonth, () => onDateFilterChanged(_DateRangeFilter.thisMonth)),
                const SizedBox(width: 6),
                _chip('Custom', dateFilter == _DateRangeFilter.custom, () => onDateFilterChanged(_DateRangeFilter.custom)),
                const SizedBox(width: 12),
                _chip('All', directionFilter == null, () => onDirectionFilterChanged(null)),
                const SizedBox(width: 6),
                _chip('Received', directionFilter == 'credit', () => onDirectionFilterChanged(directionFilter == 'credit' ? null : 'credit')),
                const SizedBox(width: 6),
                _chip('Sent', directionFilter == 'debit', () => onDirectionFilterChanged(directionFilter == 'debit' ? null : 'debit')),
                const SizedBox(width: 12),
                _chip('Completed', statusFilter == 'Completed', () => onStatusFilterChanged(statusFilter == 'Completed' ? null : 'Completed')),
                const SizedBox(width: 6),
                _chip('Pending', statusFilter == 'Pending', () => onStatusFilterChanged(statusFilter == 'Pending' ? null : 'Pending')),
                const SizedBox(width: 6),
                _chip('Refunded', statusFilter == 'Refunded', () => onStatusFilterChanged(statusFilter == 'Refunded' ? null : 'Refunded')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final LedgerEntry transaction;
  final int index;
  final VoidCallback onTap;
  const _TransactionCard({required this.transaction, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final kind = classifyTxn(t);
    final color = txnAmountColor(t);
    final d = t.createdAt.toLocal();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + (index * 30).clamp(0, 300)),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: child)),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(txnKindIcon(kind), color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      const SizedBox(height: 3),
                      Text('${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} · ${txnPaymentMethod(t)}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      if (t.orderId != null || t.referenceId != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (t.orderId != null) 'Order #${t.orderId!.length > 8 ? t.orderId!.substring(0, 8).toUpperCase() : t.orderId!.toUpperCase()}',
                            if (t.referenceId != null) 'Ref: ${t.referenceId}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${t.entryType == 'credit' ? '+' : '-'}₹${t.amount.toStringAsFixed(2)}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13.5)),
                    Text(txnDirectionLabel(t), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: txnStatusColor(t).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                      child: Text(txnStatusLabel(t), style: TextStyle(color: txnStatusColor(t), fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
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

class _EmptyState extends StatelessWidget {
  final bool hasAnyTransactions;
  final VoidCallback onGuideTap;
  const _EmptyState({required this.hasAnyTransactions, required this.onGuideTap});

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
              child: const Icon(Icons.account_balance_wallet_outlined, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(hasAnyTransactions ? 'No matching transactions' : 'Wallet is Ready', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            Text(
              hasAnyTransactions
                  ? 'Try a different search or filter.'
                  : 'Your transactions will appear here once you start receiving or withdrawing payments.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            if (!hasAnyTransactions) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onGuideTap, icon: const Icon(Icons.menu_book_outlined, size: 18), label: const Text('View Wallet Guide')),
            ],
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool busy;
  final bool canWithdraw;
  final VoidCallback onWithdraw;
  final VoidCallback onRefresh;
  final VoidCallback onStatement;
  const _BottomBar({required this.busy, required this.canWithdraw, required this.onWithdraw, required this.onRefresh, required this.onStatement});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))]),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: canWithdraw && !busy ? onWithdraw : null,
                icon: const Icon(Icons.account_balance_outlined, size: 18),
                label: const Text('Withdraw to Bank'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: busy ? null : onRefresh, icon: const Icon(Icons.refresh)),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: busy ? null : onStatement, icon: const Icon(Icons.file_download_outlined)),
          ],
        ),
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(height: 160, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22))),
          const SizedBox(height: 16),
          Row(children: List.generate(4, (i) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Container(height: 64, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))))))),
          const SizedBox(height: 16),
          ...List.generate(4, (i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Container(height: 78, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))))),
        ],
      ),
    );
  }
}
