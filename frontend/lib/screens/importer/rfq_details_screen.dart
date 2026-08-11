import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../models/rfq_report_data.dart';
import '../../models/trade.dart';
import '../../providers/providers.dart';

/// Full read-only detail view for one already-posted RFQ — reached by tapping an RFQ in the
/// Importer Dashboard's Recent Activity → Latest RFQs. Every value comes from the real RFQ
/// record via RfqReportData.fromRFQ (no hardcoded/mock data); the product image and
/// certification document, if uploaded, are shown and tappable to view full-size.
class RFQDetailsScreen extends ConsumerWidget {
  final RFQ rfq;
  const RFQDetailsScreen({super.key, required this.rfq});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authProvider);
    final d = RfqReportData.fromRFQ(
      rfq,
      buyerName: auth.currentUser?.fullName ?? '',
      buyerCompany: auth.currentUser?.companyName ?? 'Not specified',
      buyerEmail: auth.currentUser?.email ?? '',
    );

    return Scaffold(
      appBar: AppBar(title: Text(d.productName)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (d.productImageUrl != null) ...[
              _viewableImage(context, d.productImageUrl!, height: 200),
              const SizedBox(height: 16),
            ],
            _section(context, 'RFQ Overview', [
              _row('RFQ Number', d.rfqNumber),
              _row('Status', d.status),
              _row('Created', d.issueDate),
            ]),
            _section(context, 'Product Details', [
              _row('Product Name', d.productName),
              _row('HS Code', d.hsnCode),
              _row('Category', d.category),
              _row('Description', d.productDescription),
            ]),
            _section(context, 'Quantity Details', [
              _row('Quantity', '${d.quantity} ${d.unit}'),
              _row('Minimum Order Quantity', d.minOrderQty),
              _row('Packaging Type', d.packagingType),
            ]),
            _section(context, 'Pricing', [
              _row('Target Price per Unit', d.targetPrice),
              _row('Currency', d.currency),
              _row('Incoterm', d.incoterm),
            ]),
            _section(context, 'Shipping Details', [
              _row('Origin Country', d.originCountry),
              _row('Destination Country', d.destinationCountry),
              _row('Shipping Mode', d.shippingMode),
              _row('Delivery Deadline', d.deliveryDeadline),
            ]),
            _section(context, 'Additional Requirements', [
              _row('Quality Requirements', d.qualityRequirements.isEmpty ? 'Not specified' : d.qualityRequirements),
              _row('Certifications Required', d.certifications.isEmpty ? 'Not specified' : d.certifications),
              _row('Inspection Required', d.inspectionRequired ? 'Yes' : 'No'),
              _row('Packaging Instructions', d.packagingInstructions.isEmpty ? 'Not specified' : d.packagingInstructions),
              _row('Additional Notes', d.additionalNotes.isEmpty ? 'Not specified' : d.additionalNotes),
            ]),
            if (d.certificationDocumentUrl != null) ...[
              const Text('Certification Document', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12.5)),
              const SizedBox(height: 10),
              _viewableImage(context, d.certificationDocumentUrl!, height: 160),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12.5)),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }

  /// Tapping opens the full document in the browser/viewer app — same "View" pattern already
  /// used for KYC documents (launch_url on the raw file URL).
  Widget _viewableImage(BuildContext context, String url, {required double height}) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          url,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: height,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
