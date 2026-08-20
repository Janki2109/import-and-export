import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../../models/platform.dart';
import '../../services/platform_service.dart';
import 'create_ad_screen.dart';

/// Advertisement Details — full media, full text, advertiser info, and (only for the
/// advertisement's own owner) edit/delete/publish-unpublish actions. Opening this screen
/// records one view via AdvertisementService.getById (the backend increments server-side).
class AdDetailsScreen extends StatefulWidget {
  final String adId;
  final bool isOwner;
  const AdDetailsScreen({super.key, required this.adId, required this.isOwner});

  @override
  State<AdDetailsScreen> createState() => _AdDetailsScreenState();
}

class _AdDetailsScreenState extends State<AdDetailsScreen> {
  final _adService = AdvertisementService();
  late Future<Advertisement> _future;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _adService.getById(widget.adId);
  }

  void _refresh() => setState(() => _future = _adService.getById(widget.adId));

  Future<void> _editAd(Advertisement ad) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateAdScreen(
          editAdId: ad.id,
          initialTitle: ad.title,
          initialDescription: ad.description,
          initialCategory: ad.category,
          initialMediaType: ad.mediaType,
          initialImageUrl: ad.imageUrl,
          initialPrice: ad.price,
          initialContactInfo: ad.contactInfo,
        ),
      ),
    );
    if (updated == true) {
      _changed = true;
      _refresh();
    }
  }

  Future<void> _togglePublish(Advertisement ad) async {
    try {
      await _adService.setActive(ad.id, !ad.isActive);
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ad.isActive ? 'Advertisement unpublished' : 'Advertisement published'), backgroundColor: AppColors.success),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _delete(Advertisement ad) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Advertisement'),
        content: const Text('This cannot be undone. Delete this advertisement?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppColors.error), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _adService.delete(ad.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Advertisement deleted'), backgroundColor: AppColors.success));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Advertisement'),
          actions: [
            FutureBuilder<Advertisement>(
              future: _future,
              builder: (context, snapshot) {
                final ad = snapshot.data;
                if (ad == null) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Share',
                  onPressed: () => Share.share('${ad.title}\n${ad.imageUrl}'),
                );
              },
            ),
          ],
        ),
        body: FutureBuilder<Advertisement>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return Center(child: Text('Could not load advertisement.\n${snapshot.error ?? ''}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)));
            }
            final ad = snapshot.data!;
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              builder: (context, v, child) => Opacity(opacity: v, child: child),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ad.isVideo ? _AdVideoPlayer(url: ad.imageUrl) : _AdImageViewer(url: ad.imageUrl),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(ad.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
                              if (!ad.isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                                  child: const Text('Unpublished', style: TextStyle(color: AppColors.warning, fontSize: 10.5, fontWeight: FontWeight.w700)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.storefront_outlined, size: 15, color: AppColors.textSecondary),
                              const SizedBox(width: 5),
                              Expanded(child: Text(ad.advertiserName ?? 'Advertiser', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (ad.category != null) _badge(Icons.sell_outlined, ad.category!, AppColors.primary),
                              _badge(Icons.visibility_outlined, '${ad.views} views', AppColors.textSecondary),
                              _badge(Icons.event_outlined, _formatDate(ad.createdAt), AppColors.textSecondary),
                            ],
                          ),
                          if (ad.price != null) ...[
                            const SizedBox(height: 14),
                            Text('₹${ad.price!.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.success)),
                          ],
                          if (ad.description != null && ad.description!.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text('Description', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            const SizedBox(height: 6),
                            Text(ad.description!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, height: 1.5)),
                          ],
                          if (ad.contactInfo != null && ad.contactInfo!.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text('Contact', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            const SizedBox(height: 6),
                            Row(children: [const Icon(Icons.call_outlined, size: 15, color: AppColors.primary), const SizedBox(width: 6), Text(ad.contactInfo!, style: const TextStyle(fontSize: 13.5))]),
                          ],
                          if (widget.isOwner) ...[
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(onPressed: () => _editAd(ad), icon: const Icon(Icons.edit_outlined, size: 17), label: const Text('Edit')),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _togglePublish(ad),
                                    icon: Icon(ad.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 17),
                                    label: Text(ad.isActive ? 'Unpublish' : 'Publish'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _delete(ad),
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                                icon: const Icon(Icons.delete_outline, size: 17),
                                label: const Text('Delete Advertisement'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: color), const SizedBox(width: 5), Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600))]),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

/// Full-size zoomable image viewer, same InteractiveViewer pattern already used for KYC
/// document review (admin_kyc_review_screen.dart) — extracted inline here for ad media.
class _AdImageViewer extends StatelessWidget {
  final String url;
  const _AdImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 60)),
            ),
          ),
        ),
      )),
      child: AspectRatio(
        aspectRatio: 1.5,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null ? child : Container(color: Colors.grey.shade200, child: const Center(child: CircularProgressIndicator())),
          errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200, child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textSecondary, size: 40)),
        ),
      ),
    );
  }
}

/// Video ad player — thumbnail-first, tap to play, standard play/pause controls, never
/// autoplays with sound (starts paused and muted-by-default browser/OS behavior is
/// irrelevant since it simply doesn't auto-start).
class _AdVideoPlayer extends StatefulWidget {
  final String url;
  const _AdVideoPlayer({required this.url});

  @override
  State<_AdVideoPlayer> createState() => _AdVideoPlayerState();
}

class _AdVideoPlayerState extends State<_AdVideoPlayer> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _failed = false;

  Future<void> _startPlayback() async {
    setState(() => _loading = true);
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      controller.setLooping(false);
      await controller.play();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _loading = false;
      });
      controller.addListener(() => mounted ? setState(() {}) : null);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller != null && _controller!.value.isInitialized) {
      return AspectRatio(
        aspectRatio: _controller!.value.aspectRatio == 0 ? 16 / 9 : _controller!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller!),
            GestureDetector(
              onTap: () => setState(() => _controller!.value.isPlaying ? _controller!.pause() : _controller!.play()),
              child: AnimatedOpacity(
                opacity: _controller!.value.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  color: Colors.black26,
                  child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 56),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(_controller!, allowScrubbing: true, colors: const VideoProgressColors(playedColor: AppColors.primary)),
            ),
          ],
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1.5,
      child: GestureDetector(
        onTap: _loading ? null : _startPlayback,
        child: Container(
          color: Colors.black87,
          child: Center(
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : _failed
                    ? const Icon(Icons.error_outline, color: Colors.white54, size: 40)
                    : const Icon(Icons.play_circle_fill, color: Colors.white, size: 56),
          ),
        ),
      ),
    );
  }
}
