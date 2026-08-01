import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../models/company.dart';
import '../../models/user.dart';
import '../../providers/providers.dart';
import '../../services/company_service.dart';
import '../../services/profile_service.dart';
import '../../services/upload_service.dart';

/// Edits the account's core fields (photo/name/email/phone) via the new PUT /users/me,
/// and the company/business fields via the existing POST /company upsert — GST/IEC are
/// intentionally not editable here (see profile_screen.dart comment: they route through
/// the existing KYC re-verification flow instead).
class EditProfileScreen extends ConsumerStatefulWidget {
  final AppUser user;
  final Company? company;
  const EditProfileScreen({super.key, required this.user, this.company});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _companyNameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _productsCtrl;
  String? _shippingMode;

  final _profileService = ProfileService();
  final _companyService = CompanyService();
  final _uploadService = UploadService();
  final _picker = ImagePicker();

  File? _pickedPhoto;
  String? _avatarUrl;
  bool _uploadingPhoto = false;
  bool _saving = false;

  static const _shippingModes = ['air', 'sea', 'road'];
  static final _emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
  static final _phoneRegex = RegExp(r'^[0-9]{10,15}$');

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController(text: widget.user.fullName);
    _emailCtrl = TextEditingController(text: widget.user.email);
    _phoneCtrl = TextEditingController(text: widget.user.phone);
    _companyNameCtrl = TextEditingController(text: widget.company?.companyName ?? widget.user.companyName ?? '');
    _addressCtrl = TextEditingController(text: widget.company?.address ?? '');
    _productsCtrl = TextEditingController(text: widget.company?.productsImported ?? '');
    _shippingMode = widget.company?.preferredShippingMode;
    _avatarUrl = widget.user.avatarUrl;
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _pickedPhoto = File(picked.path);
      _uploadingPhoto = true;
    });
    try {
      final url = await _uploadService.uploadFile(category: 'profile', file: _pickedPhoto!, contentType: 'image/jpeg');
      if (mounted) setState(() => _avatarUrl = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo upload failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final updatedUser = await _profileService.updateProfile(
        fullName: _fullNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        avatarUrl: _avatarUrl,
      );
      await _companyService.upsert(
        companyName: _companyNameCtrl.text.trim().isEmpty ? updatedUser.fullName : _companyNameCtrl.text.trim(),
        businessType: widget.company?.businessType,
        registrationNumber: widget.company?.registrationNumber,
        address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        city: widget.company?.city,
        country: widget.company?.country,
        website: widget.company?.website,
        productsImported: _productsCtrl.text.trim().isEmpty ? null : _productsCtrl.text.trim(),
        preferredShippingMode: _shippingMode,
      );

      ref.read(authProvider).applyProfileUpdate(updatedUser);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated'), backgroundColor: AppColors.success));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        backgroundImage: _pickedPhoto != null
                            ? FileImage(_pickedPhoto!)
                            : (_avatarUrl != null ? CachedNetworkImageProvider(_avatarUrl!) as ImageProvider : null),
                        child: (_pickedPhoto == null && _avatarUrl == null)
                            ? Text(widget.user.fullName.isNotEmpty ? widget.user.fullName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 30, color: AppColors.primary, fontWeight: FontWeight.w800))
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: InkWell(
                          onTap: _uploadingPhoto ? null : _pickPhoto,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: _uploadingPhoto
                                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _fullNameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _companyNameCtrl,
                  decoration: const InputDecoration(labelText: 'Company Name', prefixIcon: Icon(Icons.apartment_outlined)),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                  validator: (v) => (v == null || !_emailRegex.hasMatch(v.trim())) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile Number', prefixIcon: Icon(Icons.phone_outlined)),
                  validator: (v) => (v == null || !_phoneRegex.hasMatch(v.trim())) ? 'Enter a valid 10-15 digit mobile number' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Business Address', prefixIcon: Icon(Icons.location_on_outlined)),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _productsCtrl,
                  decoration: const InputDecoration(labelText: 'Products Imported', prefixIcon: Icon(Icons.inventory_2_outlined)),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _shippingMode,
                  decoration: const InputDecoration(labelText: 'Preferred Shipping Mode', prefixIcon: Icon(Icons.local_shipping_outlined)),
                  items: _shippingModes.map((m) => DropdownMenuItem(value: m, child: Text(m[0].toUpperCase() + m.substring(1)))).toList(),
                  onChanged: (v) => setState(() => _shippingMode = v),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
