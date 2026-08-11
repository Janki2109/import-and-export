import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import 'auth_visuals.dart';
import 'register_screen.dart' show RoleCard;

const _rememberedEmailKey = 'remembered_login_email';
final _emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _rememberMe = false;
  // Multi-role login — same email/password, but the selected role decides which role the
  // account logs in as and which dashboard opens (see AuthProvider.login / backend
  // AuthService.Login). Defaults to 'importer', same default as the Register screen's role
  // picker this reuses (RoleCard).
  String _role = 'importer';

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 550))..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(_fade);
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_rememberedEmailKey);
    if (saved != null && mounted) {
      setState(() {
        _emailCtrl.text = saved;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // Submit logic is unchanged from the original screen — same AuthProvider.login() call,
  // same validator gating, same GoRouter-redirect-driven navigation on success.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(_rememberedEmailKey, _emailCtrl.text.trim());
    } else {
      await prefs.remove(_rememberedEmailKey);
    }

    final auth = ref.read(authProvider);
    final ok = await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text, role: _role);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage ?? 'Login failed'), backgroundColor: AppColors.error),
      );
    }
  }

  void _comingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label — coming soon.')));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: AuthColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    // Top: gradient hero with world-map + trade motif + brand mark.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                      decoration: const BoxDecoration(
                        gradient: AuthColors.gradient,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Positioned(
                            top: -20,
                            child: Opacity(
                              opacity: 0.5,
                              child: CustomPaint(size: Size(260, 260), painter: GlobePainter(color: Colors.white, strokeWidth: 0.9)),
                            ),
                          ),
                          Column(
                            children: [
                              const SizedBox(height: 8),
                              FadeTransition(
                                opacity: _fade,
                                child: const TradeIllustration(size: 120),
                              ),
                              const SizedBox(height: 12),
                              FadeTransition(
                                opacity: _fade,
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 6))],
                                  ),
                                  child: const Icon(Icons.public, color: AuthColors.primary, size: 32),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Login card.
                    Transform.translate(
                      offset: const Offset(0, -28),
                      child: FadeTransition(
                        opacity: _fade,
                        child: SlideTransition(
                          position: _slide,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 10))],
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Text('Welcome Back', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AuthColors.textPrimary)),
                                    const SizedBox(height: 6),
                                    const Text('Login to continue your global trade journey.', textAlign: TextAlign.center, style: TextStyle(color: AuthColors.textSecondary, fontSize: 13)),
                                    const SizedBox(height: 22),
                                    const Text('Login as...', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AuthColors.textPrimary)),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        RoleCard(
                                          selected: _role == 'importer',
                                          label: 'Importer',
                                          icon: Icons.shopping_cart_outlined,
                                          onTap: () => setState(() => _role = 'importer'),
                                        ),
                                        const SizedBox(width: 10),
                                        RoleCard(
                                          selected: _role == 'exporter',
                                          label: 'Exporter',
                                          icon: Icons.upload_outlined,
                                          onTap: () => setState(() => _role = 'exporter'),
                                        ),
                                        const SizedBox(width: 10),
                                        RoleCard(
                                          selected: _role == 'logistics',
                                          label: 'Logistics\nPartner',
                                          icon: Icons.local_shipping_outlined,
                                          onTap: () => setState(() => _role = 'logistics'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 22),
                                    TextFormField(
                                      controller: _emailCtrl,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: authFieldDecoration(label: 'Email', icon: Icons.email_outlined),
                                      validator: (v) => (v == null || !_emailRegex.hasMatch(v)) ? 'Enter a valid email' : null,
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _passwordCtrl,
                                      obscureText: _obscure,
                                      decoration: authFieldDecoration(
                                        label: 'Password',
                                        icon: Icons.lock_outline,
                                        suffixIcon: IconButton(
                                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AuthColors.textSecondary),
                                          onPressed: () => setState(() => _obscure = !_obscure),
                                        ),
                                      ),
                                      validator: (v) => (v == null || v.length < 8) ? 'Minimum 8 characters' : null,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Transform.scale(
                                          scale: 0.9,
                                          child: Checkbox(
                                            value: _rememberMe,
                                            activeColor: AuthColors.primary,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                            onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                          ),
                                        ),
                                        const Text('Remember Me', style: TextStyle(fontSize: 12.5, color: AuthColors.textSecondary)),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: () => _comingSoon('Password reset'),
                                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                          child: const Text('Forgot Password?', style: TextStyle(fontSize: 12.5, color: AuthColors.primary, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),
                                    GradientButton(
                                      label: 'Login',
                                      icon: Icons.arrow_forward,
                                      loading: auth.isLoading,
                                      onPressed: auth.isLoading ? null : _submit,
                                    ),
                                    const SizedBox(height: 22),
                                    const OrDivider(),
                                    const SizedBox(height: 16),
                                    const Row(
                                      children: [
                                        Expanded(
                                          child: SocialButton(
                                            label: 'Google',
                                            icon: Icon(Icons.g_mobiledata, size: 24, color: AuthColors.textPrimary),
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: SocialButton(
                                            label: 'Microsoft',
                                            icon: Icon(Icons.window_outlined, size: 18, color: AuthColors.textPrimary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account?", style: TextStyle(color: AuthColors.textSecondary, fontSize: 13.5)),
                          TextButton(
                            onPressed: () => context.push('/register'),
                            child: const Text('Create Account', style: TextStyle(color: AuthColors.primary, fontWeight: FontWeight.w700, fontSize: 13.5)),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20, top: 10),
                      child: Column(
                        children: [
                          const Text('v1.0.0', style: TextStyle(color: AuthColors.textSecondary, fontSize: 11)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () => _comingSoon('Privacy Policy'),
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 0)),
                                child: const Text('Privacy Policy', style: TextStyle(color: AuthColors.textSecondary, fontSize: 11.5)),
                              ),
                              const Text('·', style: TextStyle(color: AuthColors.textSecondary)),
                              TextButton(
                                onPressed: () => _comingSoon('Terms & Conditions'),
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 0)),
                                child: const Text('Terms & Conditions', style: TextStyle(color: AuthColors.textSecondary, fontSize: 11.5)),
                              ),
                            ],
                          ),
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
}
