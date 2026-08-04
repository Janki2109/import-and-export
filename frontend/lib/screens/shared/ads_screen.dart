import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/platform.dart';
import '../../services/platform_service.dart';

class AdsScreen extends StatefulWidget {
  const AdsScreen({super.key});
  @override
  State<AdsScreen> createState() => _AdsScreenState();
}

class _AdsScreenState extends State<AdsScreen> with SingleTickerProviderStateMixin {
  final _adService = AdvertisementService();
  late TabController _tabController;
  Future<List<Advertisement>>? _activeFuture;
  Future<List<Advertisement>>? _mineFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _activeFuture = _adService.listActive();
    _mineFuture = _adService.listMine();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _createAd() async {
    final titleCtrl = TextEditingController();
    final imageCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create Advertisement', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(controller: imageCtrl, decoration: const InputDecoration(labelText: 'Image URL')),
            const SizedBox(height: 12),
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'Target URL (optional)')),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
    if (confirmed != true || titleCtrl.text.trim().isEmpty || imageCtrl.text.trim().isEmpty) return;

    try {
      await _adService.create(
        title: titleCtrl.text.trim(),
        imageUrl: imageCtrl.text.trim(),
        targetUrl: urlCtrl.text.trim().isEmpty ? null : urlCtrl.text.trim(),
      );
      setState(() => _mineFuture = _adService.listMine());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Widget _list(Future<List<Advertisement>>? future) {
    return FutureBuilder<List<Advertisement>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final ads = snapshot.data ?? [];
        if (ads.isEmpty) {
          return const Center(child: Text('No advertisements.', style: TextStyle(color: AppColors.textSecondary)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: ads.length,
          itemBuilder: (context, i) {
            final ad = ads[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.network(ad.imageUrl, height: 120, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 120, color: Colors.grey.shade200, child: const Icon(Icons.image_not_supported_outlined))),
                  Padding(padding: const EdgeInsets.all(12), child: Text(ad.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advertisements'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Active'), Tab(text: 'Mine')]),
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _createAd, icon: const Icon(Icons.add), label: const Text('Create Ad')),
      body: TabBarView(controller: _tabController, children: [_list(_activeFuture), _list(_mineFuture)]),
    );
  }
}
