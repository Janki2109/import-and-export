import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a screen that sits at the root of the navigation stack (the four role
/// dashboards) so the Android back button doesn't instantly kill the app. First press
/// shows a "press back again to exit" toast; a second press within [window] actually
/// exits. Screens that aren't navigation roots don't need this — GoRouter/Navigator
/// already pops normally wherever there's something to pop.
class DoubleBackToExit extends StatefulWidget {
  final Widget child;
  final Duration window;
  const DoubleBackToExit({super.key, required this.child, this.window = const Duration(seconds: 2)});

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  DateTime? _lastBackPress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPress != null && now.difference(_lastBackPress!) < widget.window) {
          SystemNavigator.pop();
          return;
        }
        _lastBackPress = now;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2)),
        );
      },
      child: widget.child,
    );
  }
}
