import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import 'auth_visuals.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

final _emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
final _phoneRegex = RegExp(r'^[0-9]{10,15}$');

class _RegisterScreenState extends ConsumerState<RegisterScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  String _role = 'importer';
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  late final AnimationController _entrance;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // Submit logic is unchanged from the original screen — same fields, same
  // AuthProvider.register()/login() calls, same auto-sign-in-after-register behavior.
  // _confirmPasswordCtrl is a client-side-only typo guard (via its own validator below)
  // and is never sent to the backend.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = ref.read(authProvider);
    final ok = await auth.register(
      role: _role,
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage ?? 'Registration failed'), backgroundColor: AppColors.error),
      );
      return;
    }
    await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: AuthColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top hero with role-relevant trade motif.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
              decoration: const BoxDecoration(
                gradient: AuthColors.gradient,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Expanded(
                        child: Text('Create Account', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FadeTransition(opacity: _fade, child: const TradeIllustration(size: 96)),
                  const SizedBox(height: 10),
                  const Text('Create Your Business Account', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text("Join India's Global Trade Network", style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: FadeTransition(
                  opacity: _fade,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('I am a...', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AuthColors.textPrimary)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _RoleCard(
                              selected: _role == 'importer',
                              label: 'Importer',
                              icon: Icons.shopping_cart_outlined,
                              onTap: () => setState(() => _role = 'importer'),
                            ),
                            const SizedBox(width: 10),
                            _RoleCard(
                              selected: _role == 'exporter',
                              label: 'Exporter',
                              icon: Icons.upload_outlined,
                              onTap: () => setState(() => _role = 'exporter'),
                            ),
                            const SizedBox(width: 10),
                            _RoleCard(
                              selected: _role == 'logistics',
                              label: 'Logistics\nPartner',
                              icon: Icons.local_shipping_outlined,
                              onTap: () => setState(() => _role = 'logistics'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: authFieldDecoration(label: 'Full Name', icon: Icons.person_outline),
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: authFieldDecoration(label: 'Email', icon: Icons.email_outlined),
                          validator: (v) => (v == null || !_emailRegex.hasMatch(v)) ? 'Enter a valid email' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: authFieldDecoration(label: 'Phone', icon: Icons.phone_outlined),
                          validator: (v) => (v == null || !_phoneRegex.hasMatch(v)) ? 'Enter a valid phone' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          decoration: authFieldDecoration(
                            label: 'Password',
                            icon: Icons.lock_outline,
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AuthColors.textSecondary),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) => (v == null || v.length < 8) ? 'Minimum 8 characters' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmPasswordCtrl,
                          obscureText: _obscureConfirm,
                          decoration: authFieldDecoration(
                            label: 'Confirm Password',
                            icon: Icons.lock_outline,
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AuthColors.textSecondary),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) => (v != _passwordCtrl.text) ? 'Passwords do not match' : null,
                        ),
                        const SizedBox(height: 24),
                        GradientButton(
                          label: 'Create Account',
                          icon: Icons.arrow_forward,
                          loading: auth.isLoading,
                          onPressed: auth.isLoading ? null : _submit,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Already have an account?', style: TextStyle(color: AuthColors.textSecondary, fontSize: 13.5)),
                            TextButton(
                              onPressed: () => context.pop(),
                              child: const Text('Login', style: TextStyle(color: AuthColors.primary, fontWeight: FontWeight.w700, fontSize: 13.5)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Premium role-selection card — gradient + white icon + elevation when selected.
class _RoleCard extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _RoleCard({required this.selected, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: selected ? AuthColors.gradient : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Colors.transparent : Colors.grey.shade300),
          boxShadow: selected ? [BoxShadow(color: AuthColors.primary.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: selected ? Colors.white : AuthColors.textSecondary, size: 24),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AuthColors.textSecondary, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
