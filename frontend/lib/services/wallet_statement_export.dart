import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/constants/app_constants.dart';
import '../models/trade.dart';
import 'wallet_transaction_helpers.dart';

/// CSV is opened correctly by Excel/Sheets/Numbers alike, so it doubles as both the "CSV"
/// and "Excel" export options without needing a binary .xlsx-writing dependency.
String buildWalletStatementCsv(List<LedgerEntry> transactions) {
  final buffer = StringBuffer('Date,Time,Type,Description,Amount,Status,Reference\n');
  for (final t in transactions) {
    final d = t.createdAt.toLocal();
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final amount = (t.entryType == 'credit' ? '+' : '-') + t.amount.toStringAsFixed(2);
    final desc = t.description.replaceAll(',', ';');
    buffer.writeln('$date,$time,${txnKindLabel(classifyTxn(t))},$desc,$amount,${txnStatusLabel(t)},${t.referenceId ?? ''}');
  }
  return buffer.toString();
}

Future<Uint8List> buildWalletStatementPdf({
  required double balance,
  required List<LedgerEntry> transactions,
  required String accountName,
}) async {
  final doc = pw.Document();
  const blue = PdfColor.fromInt(0xFF0B3D91);
  const grey = PdfColor.fromInt(0xFF6B7280);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(children: [
              pw.Container(
                width: 40,
                height: 40,
                decoration: pw.BoxDecoration(color: blue, borderRadius: pw.BorderRadius.circular(8)),
                alignment: pw.Alignment.center,
                child: pw.Text('OBEI', style: pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(width: 10),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(AppConstants.appName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text('Wallet Statement', style: const pw.TextStyle(fontSize: 9, color: grey)),
              ]),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(accountName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('Generated: ${DateTime.now()}'.split('.').first, style: const pw.TextStyle(fontSize: 8, color: grey)),
            ]),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Divider(color: PdfColors.grey300),
        pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 10),
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: blue, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Available Balance', style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
              pw.Text('Rs. ${balance.toStringAsFixed(2)}', style: pw.TextStyle(color: PdfColors.white, fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {0: const pw.FlexColumnWidth(1.4), 1: const pw.FlexColumnWidth(2.4), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1)},
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7F8FA)),
              children: [
                _th('Date'),
                _th('Description'),
                _th('Type'),
                _th('Amount'),
              ],
            ),
            ...transactions.map((t) {
              final d = t.createdAt.toLocal();
              return pw.TableRow(children: [
                _td('${d.day}/${d.month}/${d.year}'),
                _td(t.description),
                _td(txnKindLabel(classifyTxn(t))),
                _td('${t.entryType == 'credit' ? '+' : '-'}Rs. ${t.amount.toStringAsFixed(2)}'),
              ]);
            }),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text('This statement reflects transactions recorded in your wallet ledger as of the generation time above.',
            style: const pw.TextStyle(fontSize: 7.5, color: grey)),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _th(String text) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _td(String text) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 8.5)),
    );

Future<Uint8List> buildTransactionReceiptPdf(LedgerEntry t) async {
  final doc = pw.Document();
  const blue = PdfColor.fromInt(0xFF0B3D91);
  const grey = PdfColor.fromInt(0xFF6B7280);
  final d = t.createdAt.toLocal();

  pw.Widget row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: grey)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Container(
              width: 36,
              height: 36,
              decoration: pw.BoxDecoration(color: blue, borderRadius: pw.BorderRadius.circular(8)),
              alignment: pw.Alignment.center,
              child: pw.Text('OBEI', style: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(width: 10),
            pw.Text('Transaction Receipt', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 16),
          pw.Divider(color: PdfColors.grey300),
          row('Transaction ID', t.id),
          row('Reference Number', t.referenceId ?? 'Not available'),
          row('Amount', '${t.entryType == 'credit' ? '+' : '-'}Rs. ${t.amount.toStringAsFixed(2)}'),
          row('GST', 'N/A'),
          row('Date', '${d.day}/${d.month}/${d.year}'),
          row('Time', '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'),
          row('Status', txnStatusLabel(t)),
          row('Payment Method', txnPaymentMethod(t)),
          pw.SizedBox(height: 8),
          pw.Text('Description', style: const pw.TextStyle(fontSize: 10, color: grey)),
          pw.SizedBox(height: 2),
          pw.Text(t.description, style: const pw.TextStyle(fontSize: 10.5)),
          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey300),
          pw.Center(child: pw.Text('Generated by ${AppConstants.appName}', style: const pw.TextStyle(fontSize: 7.5, color: grey))),
        ],
      ),
    ),
  );

  return doc.save();
}
