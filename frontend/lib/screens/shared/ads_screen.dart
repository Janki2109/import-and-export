import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/platform.dart';
import '../../services/platform_service.dart';
import 'ad_details_screen.dart';
import 'create_ad_screen.dart';

const List<String> kAdCategories = [
  'Electronics',
  'Textiles & Apparel',
  'Machinery',
  'Agriculture',
  'Chemicals',
  'Automotive',
  'Logistics Services',
  'Packaging',
  'Other',
];

/// Advertisements — a B2B advertising feed. "Feed" shows every active ad platform-wide
/// (any role can see any other role's ad — the backend has no per-role visibility rule);
/// "My Ads" shows the caller's own ads regardless of published/unpublished state, with
/// edit/delete/publish actions. Real data only — every field comes straight from
/// AdvertisementService, media is uploaded via the existing presigned-upload flow.
class AdsScreen extends StatefulWidget {
  const AdsScreen({super.key});
  @override
  State<AdsScreen> createState() => _AdsScreenState();
}

class _AdsScreenState extends State<AdsScreen> with SingleTickerProviderStateMixin {
  final _adService = AdvertisementService();
  late TabController _tabController;
  Future<List<Advertisement>>? _feedFuture;
  Future<List<Advertisement>>? _mineFuture;

  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _category;
  String? _mediaFilter; // 'image' | 'video' | null

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refresh();
  }

  void _refresh() {
    setState(() {
      _feedFuture = _adService.listActive();
      _mineFuture = _adService.listMine();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CreateAdScreen()));
    if (created == true) _refresh();
  }

  List<Advertisement> _applyFilters(List<Advertisement> ads) {
    return ads.where((a) {
      if (_query.trim().isNotEmpty) {
        final q = _query.trim().toLowerCase();
        if (!a.title.toLowerCase().contains(q) && !(a.description?.toLowerCase().contains(q) ?? false)) return false;
      }
      if (_category != null && a.category != _category) return false;
      if (_mediaFilter != null && a.mediaType != _mediaFilter) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advertisements'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Feed'), Tab(text: 'My Advertisements')]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Post Advertisement'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FeedTab(
            future: _feedFuture,
            searchCtrl: _searchCtrl,
            onSearchChanged: (v) => setState(() => _query = v),
            category: _category,
            onCategoryChanged: (c) => setState(() => _category = c),
            mediaFilter: _mediaFilter,
            onMediaFilterChanged: (m) => setState(() => _mediaFilter = m),
            applyFilters: _applyFilters,
            onRefresh: () async => _refresh(),
            onOpenAd: (ad) => _openDetails(ad, isMine: false),
          ),
          _MyAdsTab(
            future: _mineFuture,
            onRefresh: () async => _refresh(),
            onOpenAd: (ad) => _openDetails(ad, isMine: true),
          ),
        ],
      ),
    );
  }

  Future<void> _openDetails(Advertisement ad, {required bool isMine}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdDetailsScreen(adId: ad.id, isOwner: isMine)),
    );
    if (changed == true) _refresh();
  }
}

class _FeedTab extends StatelessWidget {
  final Future<List<Advertisement>>? future;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final String? category;
  final ValueChanged<String?> onCategoryChanged;
  final String? mediaFilter;
  final ValueChanged<String?> onMediaFilterChanged;
  final List<Advertisement> Function(List<Advertisement>) applyFilters;
  final Future<void> Function() onRefresh;
  final void Function(Advertisement) onOpenAd;

  const _FeedTab({
    required this.future,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.category,
    required this.onCategoryChanged,
    required this.mediaFilter,
    required this.onMediaFilterChanged,
    required this.applyFilters,
    required this.onRefresh,
    required this.onOpenAd,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: FutureBuilder<List<Advertisement>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: '${snapshot.error}', onRetry: onRefresh);
          }
          final all = snapshot.data ?? [];
          final filtered = applyFilters(all);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: searchCtrl,
                        onChanged: onSearchChanged,
                        decoration: const InputDecoration(hintText: 'Search advertisements', prefixIcon: Icon(Icons.search)),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _chip('All', category == null, () => onCategoryChanged(null)),
                            for (final c in kAdCategories) ...[
                              const SizedBox(width: 6),
                              _chip(c, category == c, () => onCategoryChanged(category == c ? null : c)),
                            ],
                            const SizedBox(width: 12),
                            _chip('Images', mediaFilter == 'image', () => onMediaFilterChanged(mediaFilter == 'image' ? null : 'image')),
                            const SizedBox(width: 6),
                            _chip('Videos', mediaFilter == 'video', () => onMediaFilterChanged(mediaFilter == 'video' ? null : 'video')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(hasAny: all.isNotEmpty),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.72),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _AdCard(ad: filtered[i], index: i, onTap: () => onOpenAd(filtered[i])),
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
    );
  }
}

class _AdCard extends StatelessWidget {
  final Advertisement ad;
  final int index;
  final VoidCallback onTap;
  const _AdCard({required this.ad, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (index * 25).clamp(0, 250)),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: child)),
      child: Material(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.15,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: ad.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Colors.grey.shade200),
                      errorWidget: (_, __, ___) => Container(color: Colors.grey.shade200, child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textSecondary)),
                    ),
                    if (ad.isVideo)
                      Container(
                        color: Colors.black.withValues(alpha: 0.15),
                        child: const Center(
                          child: Icon(Icons.play_circle_fill, color: Colors.white, size: 42),
                        ),
                      ),
                    if (!ad.isActive)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                          child: const Text('Unpublished', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ad.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(ad.advertiserName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (ad.category != null)
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                              child: Text(ad.category!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.primary, fontSize: 9.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        const Spacer(),
                        const Icon(Icons.visibility_outlined, size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 2),
                        Text('${ad.views}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyAdsTab extends StatelessWidget {
  final Future<List<Advertisement>>? future;
  final Future<void> Function() onRefresh;
  final void Function(Advertisement) onOpenAd;
  const _MyAdsTab({required this.future, required this.onRefresh, required this.onOpenAd});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: FutureBuilder<List<Advertisement>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: '${snapshot.error}', onRetry: onRefresh);
          }
          final ads = snapshot.data ?? [];
          if (ads.isEmpty) {
            return ListView(children: const [_EmptyState(hasAny: false, mine: true)]);
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: ads.length,
            itemBuilder: (context, i) {
              final ad = ads[i];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 200 + (i * 25).clamp(0, 250)),
                curve: Curves.easeOut,
                builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child)),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onOpenAd(ad),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CachedNetworkImage(imageUrl: ad.imageUrl, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: Colors.grey.shade200)),
                                  if (ad.isVideo) const ColoredBox(color: Colors.black26, child: Icon(Icons.play_arrow, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ad.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (ad.isActive ? AppColors.success : AppColors.warning).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        ad.isActive ? 'Published' : 'Unpublished',
                                        style: TextStyle(color: ad.isActive ? AppColors.success : AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.visibility_outlined, size: 12, color: AppColors.textSecondary),
                                    const SizedBox(width: 2),
                                    Text('${ad.views}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasAny;
  final bool mine;
  const _EmptyState({required this.hasAny, this.mine = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.12), AppColors.primary.withValues(alpha: 0.04)]), shape: BoxShape.circle),
              child: const Icon(Icons.campaign_outlined, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              mine ? 'No Advertisements Yet' : (hasAny ? 'No matching advertisements' : 'No Advertisements Yet'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              mine ? 'Tap "Post Advertisement" to promote your products or services.' : (hasAny ? 'Try a different search or filter.' : 'Be the first to post an advertisement.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
