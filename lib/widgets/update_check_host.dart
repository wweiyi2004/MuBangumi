import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/update_controller.dart';
import 'update_ready_dialog.dart';

/// Mounts under the signed-in shell: runs a delayed startup Shorebird check and
/// presents the Markdown restart dialog when a patch is ready.
class UpdateCheckHost extends ConsumerStatefulWidget {
  const UpdateCheckHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateCheckHost> createState() => _UpdateCheckHostState();
}

class _UpdateCheckHostState extends ConsumerState<UpdateCheckHost> {
  @override
  void initState() {
    super.initState();
    // Each HomeShell mount (including re-login) should get one startup check.
    ref.read(updateControllerProvider.notifier).resetStartupCheckGate();
    // Let the first frame settle before touching network / Shorebird.
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () async {
        if (!mounted) return;
        await ref
            .read(updateControllerProvider.notifier)
            .runStartupCheck(force: true);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateUiState>(updateControllerProvider, (previous, next) {
      if (!next.shouldPresentRestartDialog) return;
      final snapshot = next.snapshot;
      if (snapshot == null || !snapshot.isRestartReady) {
        ref.read(updateControllerProvider.notifier).acknowledgeRestartDialog();
        return;
      }
      // Defer dialog until after the current frame so listen never re-enters.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final controller = ref.read(updateControllerProvider.notifier);
        controller.acknowledgeRestartDialog();
        final restart = await showUpdateReadyDialog(
          context,
          snapshot: snapshot,
        );
        if (restart == true && mounted) {
          controller.restartApp();
        }
      });
    });
    return widget.child;
  }
}
