import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/constants/app_constants.dart';

/// Generic CSV/PDF table export shared by every Admin Panel management screen (Users,
/// Orders, Quotations, ...). CSV opens correctly in Excel/Sheets, so it covers both the
/// "Export Excel" and "Export CSV" asks without a binary .xlsx dependency.
String buildAdminCsv(List<String> headers, List<List<String>> rows) {
  final buffer = StringBuffer('${headers.join(',')}\n');
  for (final row in rows) {
    buffer.writeln(row.map((c) => c.replaceAll(',', ';')).join(','));
  }
  return buffer.toString();
}

Future<Uint8List> buildAdminTablePdf({
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
}) async {
  final doc = pw.Document();
  const blue = PdfColor.fromInt(0xFF0B3D91);
  const grey = PdfColor.fromInt(0xFF6B7280);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(children: [
              pw.Container(
                width: 34,
                height: 34,
                decoration: pw.BoxDecoration(color: blue, borderRadius: pw.BorderRadius.circular(8)),
                alignment: pw.Alignment.center,
                child: pw.Text('OBEI', style: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(width: 10),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(AppConstants.appName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(title, style: const pw.TextStyle(fontSize: 9, color: grey)),
              ]),
            ]),
            pw.Text('Generated: ${DateTime.now().toString().split('.').first}', style: const pw.TextStyle(fontSize: 8, color: grey)),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7F8FA)),
              children: headers.map((h) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(h, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)))).toList(),
            ),
            ...rows.map((row) => pw.TableRow(
                  children: row.map((c) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(c, style: const pw.TextStyle(fontSize: 8)))).toList(),
                )),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}
