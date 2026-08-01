import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final isDark = theme.mode == ThemeMode.dark ||
        (theme.mode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return IconButton(
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () => ref.read(themeProvider).toggle(),
    );
  }
}
