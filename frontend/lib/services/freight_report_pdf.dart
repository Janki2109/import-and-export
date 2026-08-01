import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/reference.dart';

/// Builds a freight-estimate PDF mirroring the on-screen result card — same pattern as
/// duty_report_pdf.dart, kept as a separate small builder per report type.
class FreightReportPdfData {
  final String reportNumber;
  final DateTime generatedAt;
  final String mode;
  final double actualWeightKg;
  final int packages;
  final String originCountry;
  final String destinationCountry;
  final bool insurance;
  final bool express;
  final FreightEstimate estimate;

  FreightReportPdfData({
    required this.reportNumber,
    required this.generatedAt,
    required this.mode,
    required this.actualWeightKg,
    required this.packages,
    required this.originCountry,
    required this.destinationCountry,
    required this.insurance,
    required this.express,
    required this.estimate,
  });
}

Future<Uint8List> buildFreightReportPdf(FreightReportPdfData data) async {
  final doc = pw.Document();
  const blue = PdfColor.fromInt(0xFF0B3D91);
  const green = PdfColor.fromInt(0xFF16A34A);
  const grey = PdfColor.fromInt(0xFF6B7280);

  final e = data.estimate;
  final freightCharges = e.chargeableWeightKg * e.ratePerKg;

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
                    pw.Text('Freight Cost Estimate', style: const pw.TextStyle(fontSize: 9, color: grey)),
                  ],
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Estimate No: ${data.reportNumber}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
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
              row('Transport Mode', data.mode.toUpperCase()),
              row('Actual Weight', '${data.actualWeightKg.toStringAsFixed(2)} kg'),
              row('Chargeable Weight', '${e.chargeableWeightKg.toStringAsFixed(2)} kg'),
              row('Number of Packages', '${data.packages}'),
              row('Origin Country', data.originCountry),
              row('Destination Country', data.destinationCountry),
              row('Insurance Required', data.insurance ? 'Yes' : 'No'),
              row('Express Delivery', data.express ? 'Yes' : 'No'),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text('COST BREAKDOWN', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: blue)),
        pw.SizedBox(height: 8),
        row('Base Freight (${e.chargeableWeightKg.toStringAsFixed(2)} kg x Rs.${e.ratePerKg.toStringAsFixed(2)}/kg)', 'Rs. ${freightCharges.toStringAsFixed(2)}'),
        row('Handling Charges', 'Rs. ${e.baseHandlingFee.toStringAsFixed(2)}'),
        row('Fuel Surcharge', 'Not included in this estimate'),
        row('Documentation Charges', 'Not included in this estimate'),
        row('Insurance', data.insurance ? 'Indicative — contact for quote' : 'Not selected'),
        row('Taxes', 'Not included in this estimate'),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: blue, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Freight', style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.Text('Rs. ${e.estimatedFreight.toStringAsFixed(2)}', style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Divider(color: PdfColors.grey300),
        pw.Text(
          'This is a system-generated estimate for planning purposes only. Actual freight charges may vary by carrier, route, and season.',
          style: const pw.TextStyle(fontSize: 7.5, color: grey),
        ),
      ],
    ),
  );

  return doc.save();
}
