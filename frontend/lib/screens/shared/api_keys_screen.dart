import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/platform_service.dart';

/// Enterprise-tier "API Access" — generate/revoke keys used as the X-API-Key header
/// on any backend endpoint (see docs at /docs on the backend for the full API reference).
class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});
  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  final _apiKeyService = ApiKeyService();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _apiKeyService.listMine();
  }

  void _refresh() => setState(() => _future = _apiKeyService.listMine());

  Future<void> _generate() async {
    final labelCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate API Key'),
        content: TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Label (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Generate')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final rawKey = await _apiKeyService.generate(label: labelCtrl.text.trim().isEmpty ? null : labelCtrl.text.trim());
      _refresh();
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Save Your API Key'),
            content: SelectableText(rawKey, style: const TextStyle(fontFamily: 'monospace')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Keys')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _generate, icon: const Icon(Icons.add), label: const Text('New Key')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final keys = snapshot.data ?? [];
            if (keys.isEmpty) {
              return const Center(child: Text('No API keys yet.', style: TextStyle(color: AppColors.textSecondary)));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: keys.length,
              itemBuilder: (context, i) {
                final k = keys[i];
                final revoked = k['revoked'] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(k['label'] ?? 'Unnamed key'),
                    subtitle: Text(revoked ? 'Revoked' : 'Active'),
                    trailing: revoked
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.error),
                            onPressed: () async {
                              await _apiKeyService.revoke(k['id']);
                              _refresh();
                            },
                          ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
