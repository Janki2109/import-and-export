import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../models/trade.dart';
import '../../services/wallet_statement_export.dart';
import '../../services/wallet_transaction_helpers.dart';

class TransactionDetailScreen extends StatefulWidget {
  final LedgerEntry transaction;
  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  bool _busy = false;

  Future<void> _downloadReceipt() async {
    setState(() => _busy = true);
    try {
      final bytes = await buildTransactionReceiptPdf(widget.transaction);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'receipt-${widget.transaction.id}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate receipt: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareReceipt() async {
    setState(() => _busy = true);
    try {
      final bytes = await buildTransactionReceiptPdf(widget.transaction);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/receipt-${widget.transaction.id}.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Transaction Receipt');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share receipt: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    final kind = classifyTxn(t);
    final color = txnAmountColor(t);
    final d = t.createdAt.toLocal();

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction Details')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withValues(alpha: 0.2))),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(txnKindIcon(kind), color: color, size: 26),
                  ),
                  const SizedBox(height: 12),
                  Text('${t.entryType == 'credit' ? '+' : '-'}₹${t.amount.toStringAsFixed(2)}', style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(txnKindLabel(kind), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: txnStatusColor(t).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                    child: Text(txnStatusLabel(t), style: TextStyle(color: txnStatusColor(t), fontWeight: FontWeight.w700, fontSize: 11.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row('Transaction ID', t.id),
                    _row('Reference Number', t.referenceId ?? 'Not available'),
                    _row('Amount', '₹${t.amount.toStringAsFixed(2)}'),
                    _row('GST', 'N/A'),
                    _row('Date', '${d.day}/${d.month}/${d.year}'),
                    _row('Time', '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'),
                    _row('Status', txnStatusLabel(t)),
                    _row('Payment Method', txnPaymentMethod(t)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Description', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(t.description, style: const TextStyle(fontSize: 13.5)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _downloadReceipt,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download Receipt'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _shareReceipt,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share Receipt'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
        ],
      ),
    );
  }
}
