import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/update_controller.dart';
import 'github_release_dialog.dart';
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
      if (next.shouldPresentRestartDialog) {
        _presentShorebirdDialog(next);
        return;
      }
      if (next.shouldPresentGithubDialog) {
        _presentGithubDialog(next);
      }
    });
    return widget.child;
  }

  void _presentShorebirdDialog(UpdateUiState next) {
    final snapshot = next.snapshot;
    if (snapshot == null || !snapshot.isRestartReady) {
      ref.read(updateControllerProvider.notifier).acknowledgeRestartDialog();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = ref.read(updateControllerProvider.notifier);
      controller.acknowledgeRestartDialog();
      final restart = await showUpdateReadyDialog(context, snapshot: snapshot);
      if (restart == true && mounted) {
        controller.restartApp();
      }
    });
  }

  void _presentGithubDialog(UpdateUiState next) {
    final release = next.githubRelease;
    final snapshot = next.snapshot;
    if (release == null || snapshot == null) {
      ref.read(updateControllerProvider.notifier).acknowledgeGithubDialog();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = ref.read(updateControllerProvider.notifier);
      controller.acknowledgeGithubDialog();
      final result = await showGithubReleaseDialog(
        context,
        currentVersion: snapshot.appVersion,
        currentBuild: snapshot.buildNumber,
        release: release,
      );
      if (result == GithubReleaseDialogResult.skip && mounted) {
        await controller.skipGithubRelease(release);
      }
    });
  }
}
