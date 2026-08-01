import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/platform.dart';
import '../../services/platform_service.dart';

/// "Find Logistics Partner" directory — exporter browses active logistics companies
/// (KYC-verified ones sorted first) and picks one instead of typing a raw user ID.
/// Returns the selected partner's user ID via Navigator.pop.
class BrowseLogisticsScreen extends StatefulWidget {
  const BrowseLogisticsScreen({super.key});
  @override
  State<BrowseLogisticsScreen> createState() => _BrowseLogisticsScreenState();
}

class _BrowseLogisticsScreenState extends State<BrowseLogisticsScreen> {
  final _directoryService = DirectoryService();
  final _controller = TextEditingController();
  List<LogisticsPartner> _results = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await _directoryService.listLogisticsPartners(query: query);
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
      appBar: AppBar(title: const Text('Find Logistics Partner')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Search by name, company, city or country',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('No logistics partners found.', style: TextStyle(color: AppColors.textSecondary)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final p = _results[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.local_shipping_outlined, color: AppColors.primary),
                          ),
                          title: Text(p.companyName ?? p.fullName),
                          subtitle: Text([
                            if (p.city != null || p.country != null) '${p.city ?? ''} ${p.country ?? ''}'.trim(),
                            if (p.vehicleTypes.isNotEmpty) p.vehicleTypes.join(', '),
                          ].where((s) => s.isNotEmpty).join(' · ')),
                          trailing: p.kycVerified
                              ? const Chip(label: Text('Verified', style: TextStyle(color: Colors.white, fontSize: 11)), backgroundColor: AppColors.success, visualDensity: VisualDensity.compact)
                              : null,
                          onTap: () => Navigator.of(context).pop(p),
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
