import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/trade_service.dart';

/// Withdraw to Bank — same TradeService.withdraw(amount) call as before (backend records
/// the ledger debit immediately; the actual bank transfer is processed manually by
/// platform ops, since there's no payout gateway wired — see WalletService.Withdraw on
/// the backend). Redesigned into its own screen instead of a plain dialog.
class WithdrawScreen extends StatefulWidget {
  final double availableBalance;
  const WithdrawScreen({super.key, required this.availableBalance});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _amountCtrl = TextEditingController();
  final _tradeService = TradeService();
  bool _withdrawing = false;
  String? _error;

  Future<void> _withdraw() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (amount > widget.availableBalance) {
      setState(() => _error = 'Amount exceeds available balance');
      return;
    }
    setState(() {
      _withdrawing = true;
      _error = null;
    });
    try {
      await _tradeService.withdraw(amount);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw to Bank')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1857C4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Available Balance', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                    const SizedBox(height: 6),
                    Text('₹${widget.availableBalance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.account_balance_outlined, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Linked Bank', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text('Contact support to link or verify your payout account', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Withdraw Amount (₹)',
                  prefixIcon: const Icon(Icons.currency_rupee),
                  suffixIcon: TextButton(
                    onPressed: () => setState(() => _amountCtrl.text = widget.availableBalance.toStringAsFixed(2)),
                    child: const Text('MAX'),
                  ),
                ),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12.5))),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _infoRow('Amount', '₹${amount.toStringAsFixed(2)}'),
                      _infoRow('Processing Fee', 'None'),
                      _infoRow('Estimated Arrival', '1–3 business days (processed by platform ops)'),
                      const Divider(height: 20),
                      _infoRow("You'll Receive", '₹${amount.toStringAsFixed(2)}', bold: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _withdrawing ? null : _withdraw,
                child: _withdrawing
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Withdraw Now'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 14 : 12.5, color: bold ? AppColors.primary : AppColors.textPrimary)),
        ],
      ),
    );
  }
}
