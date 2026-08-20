import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../../services/platform_service.dart';
import '../../services/upload_service.dart';
import 'ads_screen.dart' show kAdCategories;

/// Post/Edit Advertisement — media (image or video) is uploaded through the app's existing
/// presigned-upload flow (UploadService, category "ads") before the ad record itself is
/// created/updated, same pattern as every other upload in the app (KYC docs, POD, chat).
class CreateAdScreen extends StatefulWidget {
  /// Non-null to edit an existing ad instead of creating a new one.
  final String? editAdId;
  final String? initialTitle;
  final String? initialDescription;
  final String? initialCategory;
  final String? initialMediaType;
  final String? initialImageUrl;
  final double? initialPrice;
  final String? initialContactInfo;

  const CreateAdScreen({
    super.key,
    this.editAdId,
    this.initialTitle,
    this.initialDescription,
    this.initialCategory,
    this.initialMediaType,
    this.initialImageUrl,
    this.initialPrice,
    this.initialContactInfo,
  });

  @override
  State<CreateAdScreen> createState() => _CreateAdScreenState();
}

class _CreateAdScreenState extends State<CreateAdScreen> {
  final _adService = AdvertisementService();
  final _uploadService = UploadService();
  final _picker = ImagePicker();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  String? _category;
  String _mediaType = 'image'; // 'image' | 'video'

  Uint8List? _previewBytes;
  String? _pickedFileName;
  VideoPlayerController? _videoPreviewController;
  String? _existingMediaUrl;

  bool get _isEditing => widget.editAdId != null;
  bool _publishing = false;
  bool _pickingMedia = false;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _titleCtrl.text = widget.initialTitle ?? '';
      _descCtrl.text = widget.initialDescription ?? '';
      _category = widget.initialCategory;
      _mediaType = widget.initialMediaType ?? 'image';
      _existingMediaUrl = widget.initialImageUrl;
      if (widget.initialPrice != null) _priceCtrl.text = widget.initialPrice!.toStringAsFixed(2);
      _contactCtrl.text = widget.initialContactInfo ?? '';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _contactCtrl.dispose();
    _videoPreviewController?.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    setState(() => _pickingMedia = true);
    try {
      final XFile? picked = _mediaType == 'video'
          ? await _picker.pickVideo(source: ImageSource.gallery)
          : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      _videoPreviewController?.dispose();
      _videoPreviewController = null;
      if (_mediaType == 'video') {
        // On web, XFile.path is already a blob: URL playable via networkUrl; on mobile it's
        // a real file path — same File-vs-URL split used elsewhere in the app for pickers.
        final controller = kIsWeb ? VideoPlayerController.networkUrl(Uri.parse(picked.path)) : VideoPlayerController.file(File(picked.path));
        try {
          await controller.initialize();
          _videoPreviewController = controller;
        } catch (_) {
          controller.dispose();
        }
      }
      setState(() {
        _previewBytes = bytes;
        _pickedFileName = picked.name;
        _existingMediaUrl = null; // a freshly picked file replaces whatever was there
      });
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
  }

  void _removeMedia() {
    setState(() {
      _previewBytes = null;
      _pickedFileName = null;
      _videoPreviewController?.dispose();
      _videoPreviewController = null;
    });
  }

  Future<void> _publish() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a title'), backgroundColor: AppColors.error));
      return;
    }
    if (_previewBytes == null && _existingMediaUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an image or video'), backgroundColor: AppColors.error));
      return;
    }

    setState(() => _publishing = true);
    try {
      String mediaUrl = _existingMediaUrl ?? '';
      if (_previewBytes != null) {
        mediaUrl = await _uploadService.uploadBytes(
          category: 'ads',
          bytes: _previewBytes!,
          fileName: _pickedFileName ?? 'ad.${_mediaType == 'video' ? 'mp4' : 'jpg'}',
          contentType: _mediaType == 'video' ? 'video/mp4' : 'image/jpeg',
        );
      }

      final price = double.tryParse(_priceCtrl.text.trim());
      final description = _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
      final contact = _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim();

      if (_isEditing) {
        await _adService.update(
          widget.editAdId!,
          title: title,
          description: description,
          category: _category,
          mediaType: _mediaType,
          imageUrl: mediaUrl,
          price: price,
          contactInfo: contact,
        );
      } else {
        await _adService.create(
          title: title,
          description: description,
          category: _category,
          mediaType: _mediaType,
          imageUrl: mediaUrl,
          price: price,
          contactInfo: contact,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Advertisement updated' : 'Advertisement published'), backgroundColor: AppColors.success),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Advertisement' : 'Post Advertisement')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Text('Media Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _mediaTypeChip(
                    icon: Icons.image_outlined,
                    label: 'Image',
                    selected: _mediaType == 'image',
                    onTap: () => setState(() => _mediaType = 'image'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _mediaTypeChip(
                    icon: Icons.videocam_outlined,
                    label: 'Video',
                    selected: _mediaType == 'video',
                    onTap: () => setState(() => _mediaType = 'video'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _mediaPreview(),
            const SizedBox(height: 20),
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Advertisement Title')),
            const SizedBox(height: 12),
            TextField(controller: _descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Description / Product-Service Details', alignLabelWithHint: true)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: kAdCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price (optional)', prefixText: '₹ '),
            ),
            const SizedBox(height: 12),
            TextField(controller: _contactCtrl, decoration: const InputDecoration(labelText: 'Contact Information (optional)')),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _publishing ? null : _publish,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _publishing
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEditing ? 'Save Changes' : 'Publish Advertisement'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaTypeChip({required IconData icon, required String label, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: () {
        onTap();
        _removeMedia();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
          border: Border.all(color: selected ? AppColors.primary : Colors.grey.shade300, width: selected ? 1.6 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: selected ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _mediaPreview() {
    final hasNewMedia = _previewBytes != null;
    final hasExisting = _existingMediaUrl != null && _existingMediaUrl!.isNotEmpty;

    if (!hasNewMedia && !hasExisting) {
      return InkWell(
        onTap: _pickingMedia ? null : _pickMedia,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.04),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.25), style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(16),
          ),
          child: _pickingMedia
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_mediaType == 'video' ? Icons.video_call_outlined : Icons.add_photo_alternate_outlined, size: 40, color: AppColors.primary),
                    const SizedBox(height: 8),
                    Text('Select ${_mediaType == 'video' ? 'a video' : 'an image'}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(
            height: 200,
            width: double.infinity,
            child: hasNewMedia
                ? (_mediaType == 'video'
                    ? (_videoPreviewController != null && _videoPreviewController!.value.isInitialized
                        ? AspectRatio(aspectRatio: _videoPreviewController!.value.aspectRatio, child: VideoPlayer(_videoPreviewController!))
                        : Container(color: Colors.black87, child: const Center(child: Icon(Icons.movie_outlined, color: Colors.white, size: 40))))
                    : Image.memory(_previewBytes!, fit: BoxFit.cover))
                : Image.network(_existingMediaUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200)),
          ),
          if (hasNewMedia && _mediaType == 'video' && _videoPreviewController != null)
            Positioned.fill(
              child: Center(
                child: IconButton(
                  icon: Icon(_videoPreviewController!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white, size: 48),
                  onPressed: () => setState(() {
                    _videoPreviewController!.value.isPlaying ? _videoPreviewController!.pause() : _videoPreviewController!.play();
                  }),
                ),
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              children: [
                _mediaActionButton(Icons.swap_horiz, _pickMedia),
                const SizedBox(width: 6),
                _mediaActionButton(Icons.close, _removeMedia),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mediaActionButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}
