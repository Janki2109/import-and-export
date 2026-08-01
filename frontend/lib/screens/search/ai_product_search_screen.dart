import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reference.dart';
import '../../services/search_service.dart';

/// Free-text product description -> AI-suggested HS codes, grounded on our own reference table
/// (the backend only ever returns codes we actually have on file, never an invented one).
class AIProductSearchScreen extends StatefulWidget {
  const AIProductSearchScreen({super.key});
  @override
  State<AIProductSearchScreen> createState() => _AIProductSearchScreenState();
}

class _AIProductSearchScreenState extends State<AIProductSearchScreen> {
  final _searchService = SearchService();
  final _controller = TextEditingController();
  List<AIProductMatch> _matches = [];
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _matches = [];
    });
    try {
      final results = await _searchService.aiProductSearch(_controller.text.trim());
      if (mounted) setState(() => _matches = results);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _confidenceColor(String confidence) {
    switch (confidence.toLowerCase()) {
      case 'high':
        return AppColors.success;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Product Search')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Describe the product in plain language, e.g. "wireless bluetooth earbuds with charging case"',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loading ? null : _search,
                icon: _loading
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(_loading ? 'Searching...' : 'Find Matching HS Codes'),
              ),
              const SizedBox(height: 16),
              if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
              Expanded(
                child: _matches.isEmpty
                    ? const Center(child: Text('Matches will appear here.', style: TextStyle(color: AppColors.textSecondary)))
                    : ListView.builder(
                        itemCount: _matches.length,
                        itemBuilder: (context, i) {
                          final m = _matches[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(m.hsCode, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                      Chip(
                                        label: Text(m.confidence, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                        backgroundColor: _confidenceColor(m.confidence),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(m.description),
                                  if (m.reason.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(m.reason, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontStyle: FontStyle.italic)),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
