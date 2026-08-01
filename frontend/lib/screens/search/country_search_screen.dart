import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reference.dart';
import '../../services/search_service.dart';

class CountrySearchScreen extends StatefulWidget {
  const CountrySearchScreen({super.key});
  @override
  State<CountrySearchScreen> createState() => _CountrySearchScreenState();
}

class _CountrySearchScreenState extends State<CountrySearchScreen> {
  final _searchService = SearchService();
  final _controller = TextEditingController();
  List<Country> _results = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await _searchService.searchCountries(query.trim());
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
      appBar: AppBar(title: const Text('Country Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Search by country name or ISO code',
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
                ? const Center(child: Text('No matches found.', style: TextStyle(color: AppColors.textSecondary)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final c = _results[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${c.iso2} · ${c.region}'),
                          trailing: c.isRestricted
                              ? const Chip(label: Text('Restricted', style: TextStyle(color: Colors.white, fontSize: 11)), backgroundColor: AppColors.error)
                              : null,
                          onTap: () => showModalBottomSheet(
                            context: context,
                            builder: (_) => _CountryDetailSheet(country: c),
                          ),
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

class _CountryDetailSheet extends StatelessWidget {
  final Country country;
  const _CountryDetailSheet({required this.country});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(country.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${country.iso2} · ${country.region}', style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          if (country.isRestricted)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.error),
                  SizedBox(width: 8),
                  Expanded(child: Text('Trade with this country is restricted or sanctioned.', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (country.notes != null) Text(country.notes!),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
