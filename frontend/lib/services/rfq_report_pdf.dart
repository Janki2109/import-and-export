import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/constants/app_constants.dart';
import '../models/rfq_report_data.dart';

/// Builds the RFQ document PDF (used for both the pre-submit Preview and the post-submit
/// Report) — professional A4 layout with company branding, buyer/supplier/product tables,
/// terms, and signature/stamp placeholders.
Future<Uint8List> buildRfqReportPdf(RfqReportData d, {required String title}) async {
  final doc = pw.Document();
  const blue = PdfColor.fromInt(0xFF0B3D91);
  const grey = PdfColor.fromInt(0xFF6B7280);

  pw.Widget kv(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 9.5, color: grey)),
            pw.Text(value, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  pw.Widget section(String title, int colorInt, List<pw.Widget> children) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF7F8FA), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(colorInt))),
            pw.SizedBox(height: 6),
            ...children,
          ],
        ),
      );

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
                    pw.Text(AppConstants.appName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.Text(title, style: const pw.TextStyle(fontSize: 9, color: grey)),
                  ],
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('RFQ No: ${d.rfqNumber}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Text('Issued: ${d.issueDate}', style: const pw.TextStyle(fontSize: 8, color: grey)),
                pw.Text('Status: ${d.status}', style: const pw.TextStyle(fontSize: 8, color: grey)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: section('BUYER DETAILS', 0xFF16A34A, [
                kv('Name', d.buyerName),
                kv('Company', d.buyerCompany),
                kv('Email', d.buyerEmail),
              ]),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: section('SUPPLIER DETAILS', 0xFFFF7A00, [
                kv('Assigned Supplier', d.supplierName),
              ]),
            ),
          ],
        ),
        section('PRODUCT INFORMATION', 0xFF0B3D91, [
          kv('Product Name', d.productName),
          kv('HS Code', d.hsnCode),
          kv('Category', d.category),
          kv('Description', d.productDescription),
        ]),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: section('QUANTITY', 0xFF0B3D91, [
                kv('Quantity', '${d.quantity} ${d.unit}'),
                kv('Min. Order Qty', d.minOrderQty),
                kv('Packaging Type', d.packagingType),
              ]),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: section('PRICING', 0xFF0B3D91, [
                kv('Target Price', '${d.currency} ${d.targetPrice}'),
                kv('Incoterm', d.incoterm),
              ]),
            ),
          ],
        ),
        section('SHIPPING INFORMATION', 0xFF0B3D91, [
          kv('Origin Country', d.originCountry),
          kv('Destination Country', d.destinationCountry),
          kv('Shipping Mode', d.shippingMode),
          kv('Delivery Deadline', d.deliveryDeadline),
        ]),
        if (d.qualityRequirements.isNotEmpty || d.certifications.isNotEmpty || d.packagingInstructions.isNotEmpty || d.additionalNotes.isNotEmpty)
          section('ADDITIONAL REQUIREMENTS', 0xFF0B3D91, [
            if (d.qualityRequirements.isNotEmpty) kv('Quality Requirements', d.qualityRequirements),
            if (d.certifications.isNotEmpty) kv('Certifications Required', d.certifications),
            kv('Inspection Required', d.inspectionRequired ? 'Yes' : 'No'),
            if (d.packagingInstructions.isNotEmpty) kv('Packaging Instructions', d.packagingInstructions),
            if (d.additionalNotes.isNotEmpty) kv('Additional Notes', d.additionalNotes),
          ]),
        pw.SizedBox(height: 8),
        pw.Text('TERMS & CONDITIONS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: blue)),
        pw.SizedBox(height: 4),
        pw.Text(RfqReportData.termsAndConditions, style: const pw.TextStyle(fontSize: 8, color: grey, lineSpacing: 2)),
        pw.SizedBox(height: 24),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(width: 140, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400))), height: 30),
                pw.SizedBox(height: 4),
                pw.Text('Authorized Signature', style: const pw.TextStyle(fontSize: 8, color: grey)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 70,
                  height: 50,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
                  alignment: pw.Alignment.center,
                  child: pw.Text('Company\nStamp', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7, color: grey)),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Divider(color: PdfColors.grey300),
        pw.Center(
          child: pw.Text('Generated by ${AppConstants.appName}', style: const pw.TextStyle(fontSize: 7.5, color: grey)),
        ),
      ],
    ),
  );

  return doc.save();
}
