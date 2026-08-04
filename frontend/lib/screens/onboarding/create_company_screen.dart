import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/company_service.dart';

/// Onboarding step: Login/Register -> Select Role -> Create Company -> KYC -> Dashboard.
/// GoRouter redirects here automatically once a freshly-registered user is authenticated
/// but has no company profile yet.
class CreateCompanyScreen extends ConsumerStatefulWidget {
  const CreateCompanyScreen({super.key});
  @override
  ConsumerState<CreateCompanyScreen> createState() => _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends ConsumerState<CreateCompanyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyService = CompanyService();
  final _nameCtrl = TextEditingController();
  final _businessTypeCtrl = TextEditingController();
  final _regNumberCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _businessTypeCtrl.dispose();
    _regNumberCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _companyService.upsert(
        companyName: _nameCtrl.text.trim(),
        businessType: _businessTypeCtrl.text.trim().isEmpty ? null : _businessTypeCtrl.text.trim(),
        registrationNumber: _regNumberCtrl.text.trim().isEmpty ? null : _regNumberCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        country: _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
        website: _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
      );
      // Refresh onboarding flags so the router's redirect sends us to KYC next.
      await ref.read(authProvider).refreshOnboardingStatus();
      if (mounted) context.go('/kyc-onboarding');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Company'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tell us about your company', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Company Name'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(controller: _businessTypeCtrl, decoration: const InputDecoration(labelText: 'Business Type (e.g. Manufacturer, Trading)')),
                const SizedBox(height: 14),
                TextFormField(controller: _regNumberCtrl, decoration: const InputDecoration(labelText: 'Registration Number (optional)')),
                const SizedBox(height: 14),
                TextFormField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Address'), maxLines: 2),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: TextFormField(controller: _cityCtrl, decoration: const InputDecoration(labelText: 'City'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextFormField(controller: _countryCtrl, decoration: const InputDecoration(labelText: 'Country'))),
                ]),
                const SizedBox(height: 14),
                TextFormField(controller: _websiteCtrl, decoration: const InputDecoration(labelText: 'Website (optional)')),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
