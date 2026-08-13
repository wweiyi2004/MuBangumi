import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import '../core/shortcuts/app_shortcut.dart';
import '../state/app_shortcut_controller.dart';

/// Registers launcher shortcuts and parks the tapped one until HomeShell
/// can open it (after sign-in / first frame).
class AppShortcutHost extends ConsumerStatefulWidget {
  const AppShortcutHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShortcutHost> createState() => _AppShortcutHostState();
}

class _AppShortcutHostState extends ConsumerState<AppShortcutHost> {
  final _quickActions = const QuickActions();

  @override
  void initState() {
    super.initState();
    if (AppShortcut.isSupported) unawaited(_bind());
  }

  Future<void> _bind() async {
    try {
      await _quickActions.initialize((type) {
        final shortcut = AppShortcut.tryParse(type);
        if (shortcut == null) return;
        ref.read(pendingAppShortcutProvider.notifier).offer(shortcut);
      });
    } catch (_) {
      // Desktop and older Android silently skip shortcuts.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
