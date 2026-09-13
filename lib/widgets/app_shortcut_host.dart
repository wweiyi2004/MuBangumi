import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import '../core/shortcuts/app_shortcut.dart';
import '../state/app_shortcut_controller.dart';
import '../state/shared_link_controller.dart';
import '../core/shortcuts/shared_link_bridge.dart';

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
  final _sharedLinks = SharedLinkBridge();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_sharedLinks.resume()),
    );
    unawaited(
      _sharedLinks.bind((text) {
        if (mounted) ref.read(pendingSharedLinksProvider.notifier).offer(text);
      }),
    );
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

  @override
  void dispose() {
    _lifecycle.dispose();
    _sharedLinks.dispose();
    super.dispose();
  }
}
