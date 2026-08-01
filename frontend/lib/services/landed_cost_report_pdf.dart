import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/reference.dart';

/// Builds the Landed Cost report PDF — mirrors the on-screen report card. The duty
/// sub-breakdown (BCD/SWS/IGST) is optional supplemental data (see comment in the screen
/// file for how it's obtained); when unavailable, only the backend's authoritative
/// `totalDuty` and `totalLandedCost` are shown.
class LandedCostReportPdfData {
  final String reportNumber;
  final DateTime generatedAt;
  final String hsCode;
  final String productName;
  final LandedCostBreakdown breakdown;
  final DutyBreakdown? dutyDetail;

  LandedCostReportPdfData({
    required this.reportNumber,
    required this.generatedAt,
    required this.hsCode,
    required this.productName,
    required this.breakdown,
    this.dutyDetail,
  });
}

Future<Uint8List> buildLandedCostReportPdf(LandedCostReportPdfData data) async {
  final doc = pw.Document();
  const blue = PdfColor.fromInt(0xFF0B3D91);
  const green = PdfColor.fromInt(0xFF16A34A);
  const orange = PdfColor.fromInt(0xFFFF7A00);
  const grey = PdfColor.fromInt(0xFF6B7280);

  final b = data.breakdown;
  final d = data.dutyDetail;

  pw.Widget row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
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
                    pw.Text('Landed Cost Report', style: const pw.TextStyle(fontSize: 9, color: grey)),
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
              row('Product', data.productName),
              row('FOB Value', 'Rs. ${b.fobValue.toStringAsFixed(2)}'),
              row('Freight', 'Rs. ${b.freight.toStringAsFixed(2)}'),
              row('Insurance', 'Rs. ${b.insurance.toStringAsFixed(2)}'),
              row('Other Charges', 'Rs. ${b.otherCharges.toStringAsFixed(2)}'),
              row('Assessable / CIF Value', 'Rs. ${b.cifValue.toStringAsFixed(2)}'),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text('DUTY COMPONENTS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: orange)),
        pw.SizedBox(height: 8),
        row('Basic Customs Duty (BCD)', d != null ? 'Rs. ${d.basicCustomsDuty.toStringAsFixed(2)}' : 'N/A'),
        row('Social Welfare Surcharge', d != null ? 'Rs. ${d.socialWelfareSurcharge.toStringAsFixed(2)}' : 'N/A'),
        row('IGST', d != null ? 'Rs. ${d.igst.toStringAsFixed(2)}' : 'N/A'),
        row('GST Compensation Cess', 'Not applicable to this HS code'),
        row('Total Duty', 'Rs. ${b.totalDuty.toStringAsFixed(2)}'),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: blue, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Final Landed Cost', style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.Text('Rs. ${b.totalLandedCost.toStringAsFixed(2)}', style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
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
