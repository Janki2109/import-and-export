import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

/// First screen a brand-new user sees, before language selection and login/register.
/// Shown once — [AppRouter] marks it seen and never routes back here after login.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.public, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 28),
              Text('One Bharat Export-Import', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text(
                'Connect with verified importers, exporters and logistics partners worldwide — with escrow-protected payments on every order.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.4),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => context.go('/language'),
                child: const Text('Get Started'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
