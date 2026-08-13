import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/shortcuts/app_shortcut.dart';

class PendingAppShortcut extends StateNotifier<AppShortcut?> {
  PendingAppShortcut() : super(null);

  void offer(AppShortcut shortcut) => state = shortcut;

  AppShortcut? take() {
    final value = state;
    state = null;
    return value;
  }
}

final pendingAppShortcutProvider =
    StateNotifierProvider<PendingAppShortcut, AppShortcut?>(
      (ref) => PendingAppShortcut(),
    );
