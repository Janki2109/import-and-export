import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/company.dart';
import '../../services/company_service.dart';
import 'company_profile_screen.dart';

/// Journey 3 — the importer-facing supplier directory: browse/search exporter companies
/// instead of typing/pasting a raw exporter user ID. Tapping a result opens the company's
/// full profile (CompanyProfileScreen); "pick" mode (picking=true) instead pops the selected
/// listing straight back to the caller, for screens that just need to select an exporter
/// (e.g. New Order) without leaving to view the profile first.
class BrowseExportersScreen extends StatefulWidget {
  final bool picking;
  const BrowseExportersScreen({super.key, this.picking = false});

  @override
  State<BrowseExportersScreen> createState() => _BrowseExportersScreenState();
}

class _BrowseExportersScreenState extends State<BrowseExportersScreen> {
  final _companyService = CompanyService();
  final _controller = TextEditingController();
  List<DirectoryListing> _results = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await _companyService.listDirectory(search: query);
      if (mounted) setState(() => _results = results);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Suppliers')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Search by company, city or country',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('No suppliers found.', style: TextStyle(color: AppColors.textSecondary)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final d = _results[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.storefront_outlined, color: AppColors.primary),
                          ),
                          title: Text(d.companyName),
                          subtitle: Text([
                            if (d.city != null || d.country != null) '${d.city ?? ''} ${d.country ?? ''}'.trim(),
                            if (d.businessType != null) d.businessType!,
                            '${d.productCount} product${d.productCount == 1 ? '' : 's'}',
                          ].where((s) => s.isNotEmpty).join(' · ')),
                          trailing: d.avgRating != null
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star, size: 16, color: Colors.amber),
                                    const SizedBox(width: 2),
                                    Text(d.avgRating!.toStringAsFixed(1)),
                                  ],
                                )
                              : null,
                          onTap: () async {
                            if (widget.picking) {
                              Navigator.of(context).pop(d);
                              return;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => CompanyProfileScreen(companyId: d.companyId)),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
