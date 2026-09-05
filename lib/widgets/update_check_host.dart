import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/update_controller.dart';
import 'github_release_dialog.dart';
import 'update_ready_dialog.dart';

/// Mounts under the root route, including login: runs a delayed Shorebird check and
/// presents the Markdown restart dialog when a patch is ready.
class UpdateCheckHost extends ConsumerStatefulWidget {
  const UpdateCheckHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateCheckHost> createState() => _UpdateCheckHostState();
}

class _UpdateCheckHostState extends ConsumerState<UpdateCheckHost>
    with WidgetsBindingObserver {
  Timer? _startupTimer;
  bool _dialogScheduled = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Let the first frame settle before touching network / Shorebird.
    _startupTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      await ref.read(updateControllerProvider.notifier).runStartupCheck();
    });
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !(_startupTimer?.isActive ?? false)) {
      unawaited(ref.read(updateControllerProvider.notifier).runStartupCheck());
    }
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
    if (_dialogScheduled) return;
    final snapshot = next.snapshot;
    if (snapshot == null || !snapshot.isRestartReady) {
      ref.read(updateControllerProvider.notifier).acknowledgeRestartDialog();
      return;
    }
    _dialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = ref.read(updateControllerProvider.notifier);
      controller.acknowledgeRestartDialog();
      final restart = await showUpdateReadyDialog(context, snapshot: snapshot);
      _dialogScheduled = false;
      if (restart == true && mounted) {
        controller.restartApp();
      }
    });
  }

  void _presentGithubDialog(UpdateUiState next) {
    if (_dialogScheduled) return;
    final release = next.githubRelease;
    final snapshot = next.snapshot;
    if (release == null || snapshot == null) {
      ref.read(updateControllerProvider.notifier).acknowledgeGithubDialog();
      return;
    }
    _dialogScheduled = true;
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
      _dialogScheduled = false;
      if (result == GithubReleaseDialogResult.skip && mounted) {
        await controller.skipGithubRelease(release);
      }
    });
  }
}
