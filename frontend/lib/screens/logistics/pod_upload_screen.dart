import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../services/order_service.dart';
import '../../services/upload_service.dart';

/// Logistics partner captures/picks the delivery photo, uploads it to S3, then submits
/// it as Proof of Delivery for the given shipment — the final step before the importer
/// can confirm delivery and release escrow.
class PODUploadScreen extends StatefulWidget {
  final String shipmentId;
  const PODUploadScreen({super.key, required this.shipmentId});
  @override
  State<PODUploadScreen> createState() => _PODUploadScreenState();
}

class _PODUploadScreenState extends State<PODUploadScreen> {
  final _picker = ImagePicker();
  final _uploadService = UploadService();
  final _orderService = OrderService();
  final _remarksCtrl = TextEditingController();
  File? _photo;
  bool _uploading = false;
  bool _submitting = false;

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  Future<void> _submit() async {
    if (_photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Take a delivery photo first')));
      return;
    }
    setState(() => _uploading = true);
    try {
      final fileUrl = await _uploadService.uploadFile(category: 'pod', file: _photo!, contentType: 'image/jpeg');
      setState(() {
        _uploading = false;
        _submitting = true;
      });
      await _orderService.uploadPOD(
        shipmentId: widget.shipmentId,
        fileUrl: fileUrl,
        remarks: _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proof of delivery uploaded.'), backgroundColor: AppColors.success),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) {
        setState(() {
        _uploading = false;
        _submitting = false;
      });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _uploading || _submitting;
    return Scaffold(
      appBar: AppBar(title: const Text('Proof of Delivery')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: busy ? null : _pickPhoto,
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _photo == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_outlined, size: 40, color: AppColors.textSecondary),
                            SizedBox(height: 8),
                            Text('Tap to capture delivery photo', style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        )
                      : ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(_photo!, fit: BoxFit.cover)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _remarksCtrl,
                decoration: const InputDecoration(labelText: 'Remarks (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: busy ? null : _submit,
                child: busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_uploading ? 'Uploading...' : 'Submit Proof of Delivery'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
