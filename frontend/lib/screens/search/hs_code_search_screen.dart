import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reference.dart';
import '../../services/search_service.dart';

class HSCodeSearchScreen extends StatefulWidget {
  const HSCodeSearchScreen({super.key});
  @override
  State<HSCodeSearchScreen> createState() => _HSCodeSearchScreenState();
}

class _HSCodeSearchScreenState extends State<HSCodeSearchScreen> {
  final _searchService = SearchService();
  final _controller = TextEditingController();
  List<HSCode> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search(''); // load the full HS code list up front
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _searchService.searchHSCodes(query.trim());
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HS Code Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Search by code or product description',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : (_controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _controller.clear();
                              _search('');
                            },
                          )
                        : null),
              ),
              onChanged: _search,
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${_results.length} HS code${_results.length == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _results.isEmpty && !_loading
                ? const Center(child: Text('No matching HS codes found.', style: TextStyle(color: AppColors.textSecondary)))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08)),
                        columns: const [
                          DataColumn(label: Text('HS Code', style: TextStyle(fontWeight: FontWeight.w800))),
                          DataColumn(label: Text('Description', style: TextStyle(fontWeight: FontWeight.w800))),
                          DataColumn(label: Text('Chapter', style: TextStyle(fontWeight: FontWeight.w800))),
                          DataColumn(label: Text('BCD %', style: TextStyle(fontWeight: FontWeight.w800)), numeric: true),
                          DataColumn(label: Text('IGST %', style: TextStyle(fontWeight: FontWeight.w800)), numeric: true),
                        ],
                        rows: _results
                            .map((h) => DataRow(cells: [
                                  DataCell(Text(h.code, style: const TextStyle(fontWeight: FontWeight.w700))),
                                  DataCell(SizedBox(width: 220, child: Text(h.description, softWrap: true))),
                                  DataCell(Text(h.chapter)),
                                  DataCell(Text(h.basicCustomsDutyPercent.toStringAsFixed(0))),
                                  DataCell(Text(h.igstPercent.toStringAsFixed(0))),
                                ]))
                            .toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
