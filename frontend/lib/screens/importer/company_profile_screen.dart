import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/company.dart';
import '../../models/platform.dart';
import '../../services/company_service.dart';
import 'create_order_screen.dart';
import 'create_rfq_screen.dart';

/// Journey 3 — "open company profile": details, certifications, products, ratings, and average
/// response time, all fetched in one call. From here the importer can request a quotation
/// (targeted RFQ) or create a direct order against this exporter — replacing the old flow where
/// the importer had to already know and paste the exporter's raw user ID.
class CompanyProfileScreen extends StatefulWidget {
  final String companyId;
  const CompanyProfileScreen({super.key, required this.companyId});

  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  final _companyService = CompanyService();
  CompanyProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _companyService.getProfile(widget.companyId);
      if (mounted) setState(() => _profile = profile);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_profile?.company.companyName ?? 'Supplier Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
              : _profile == null
                  ? const SizedBox.shrink()
                  : _buildBody(_profile!),
    );
  }

  Widget _buildBody(CompanyProfile profile) {
    final company = profile.company;
    final products = profile.productsJson.map((e) => Product.fromJson(e)).toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: const Icon(Icons.storefront_outlined, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(company.companyName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                      if (company.city != null || company.country != null)
                        Text('${company.city ?? ''} ${company.country ?? ''}'.trim(), style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _StatCard(icon: Icons.star_outline, label: 'Rating', value: profile.avgRating != null ? '${profile.avgRating!.toStringAsFixed(1)} (${profile.ratingCount})' : 'No ratings yet')),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(icon: Icons.timer_outlined, label: 'Avg Response', value: profile.avgResponseTimeHours != null ? '${profile.avgResponseTimeHours!.toStringAsFixed(1)}h' : 'N/A')),
              ],
            ),
            const SizedBox(height: 20),
            if (company.certifications.isNotEmpty) ...[
              const Text('Certifications', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: company.certifications
                    .map((cert) => Chip(label: Text(cert), avatar: const Icon(Icons.verified_outlined, size: 16)))
                    .toList(),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Products', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text('${products.length}', style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 8),
            if (products.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No products listed yet.', style: TextStyle(color: AppColors.textSecondary)),
              )
            else
              ...products.map((p) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(p.name),
                      subtitle: Text('₹${p.unitPrice.toStringAsFixed(2)} / ${p.unit} · MOQ ${p.minOrderQty.toStringAsFixed(0)}'),
                    ),
                  )),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CreateRFQScreen(targetExporterId: company.userId, targetCompanyName: company.companyName)),
                    ),
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('Request Quotation'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CreateOrderScreen(exporterId: company.userId, exporterName: company.companyName)),
                    ),
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('Create Order'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}
