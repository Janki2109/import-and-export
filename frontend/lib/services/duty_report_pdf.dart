import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/reference.dart';

/// Builds a customs-duty-worksheet-style PDF (ICEGATE-inspired layout) from a completed
/// duty calculation — mirrors the on-screen report so "Save as PDF" and the visible report
/// never drift out of sync.
class DutyReportPdfData {
  final String reportNumber;
  final DateTime generatedAt;
  final String hsCode;
  final String productName;
  final String importCountry;
  final DutyBreakdown breakdown;

  DutyReportPdfData({
    required this.reportNumber,
    required this.generatedAt,
    required this.hsCode,
    required this.productName,
    required this.importCountry,
    required this.breakdown,
  });
}

Future<Uint8List> buildDutyReportPdf(DutyReportPdfData data) async {
  final doc = pw.Document();
  const blue = PdfColor.fromInt(0xFF0B3D91);
  const green = PdfColor.fromInt(0xFF16A34A);
  const orange = PdfColor.fromInt(0xFFFF7A00);
  const grey = PdfColor.fromInt(0xFF6B7280);

  final b = data.breakdown;
  final bcdPercent = b.assessableValue > 0 ? (b.basicCustomsDuty / b.assessableValue * 100) : 0;
  final igstBase = b.assessableValue + b.basicCustomsDuty + b.socialWelfareSurcharge;
  final igstPercent = igstBase > 0 ? (b.igst / igstBase * 100) : 0;

  pw.Widget row(String label, String value, {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
        ],
      ),
    );
  }

  pw.Widget calcRow(String label, String formula, String value) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFFFF3E8), borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: orange)),
              pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(formula, style: const pw.TextStyle(fontSize: 8, color: grey)),
        ],
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                pw.Container(
                  width: 40,
                  height: 40,
                  decoration: pw.BoxDecoration(color: blue, borderRadius: pw.BorderRadius.circular(8)),
                  alignment: pw.Alignment.center,
                  child: pw.Text('OBEI', style: pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('One Bharat Export-Import', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Customs Duty Calculation Report', style: const pw.TextStyle(fontSize: 9, color: grey)),
                  ],
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Report No: ${data.reportNumber}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Text('${data.generatedAt}', style: const pw.TextStyle(fontSize: 8, color: grey)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFEFF6E9), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('SHIPMENT DETAILS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: green)),
              pw.SizedBox(height: 6),
              row('HS Code', data.hsCode),
              row('Product Name', data.productName),
              row('Import Country', data.importCountry),
              row('CIF / Assessable Value', 'Rs. ${b.assessableValue.toStringAsFixed(2)}'),
              row('Landing Charges', 'Included in assessable value'),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text('DUTY CALCULATION', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: orange)),
        pw.SizedBox(height: 8),
        calcRow('Basic Customs Duty (BCD)', 'Assessable Value x ${bcdPercent.toStringAsFixed(1)}%', 'Rs. ${b.basicCustomsDuty.toStringAsFixed(2)}'),
        calcRow('Social Welfare Surcharge', 'BCD x 10%', 'Rs. ${b.socialWelfareSurcharge.toStringAsFixed(2)}'),
        calcRow('Anti-Dumping Duty', 'Not applicable to this HS code', 'N/A'),
        calcRow('Safeguard Duty', 'Not applicable to this HS code', 'N/A'),
        calcRow('Compensation Cess', 'Not applicable to this HS code', 'N/A'),
        calcRow('IGST', '(Assessable Value + BCD + SWS) x ${igstPercent.toStringAsFixed(1)}%', 'Rs. ${b.igst.toStringAsFixed(2)}'),
        calcRow('GST Compensation Cess', 'Not applicable to this HS code', 'N/A'),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: blue, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Duty Payable', style: pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Rs. ${b.totalDutyPayable.toStringAsFixed(2)}', style: pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Landed Cost', style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Rs. ${b.totalLandedValue.toStringAsFixed(2)}', style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Divider(color: PdfColors.grey300),
        pw.Text(
          'This is a system-generated estimate for planning purposes only. Verify final classification and duty with a licensed customs broker before filing.',
          style: const pw.TextStyle(fontSize: 7.5, color: grey),
        ),
      ],
    ),
  );

  return doc.save();
}
