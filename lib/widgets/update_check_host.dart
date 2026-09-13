import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/update_controller.dart';
import 'github_release_dialog.dart';
import 'update_ready_dialog.dart';

/// Checks silently; a small in-page notice never steals keyboard or route focus.
class UpdateCheckHost extends ConsumerStatefulWidget {
  const UpdateCheckHost({
    super.key,
    required this.child,
    this.allowNotices = true,
  });
  final Widget child;
  final bool allowNotices;
  @override
  ConsumerState<UpdateCheckHost> createState() => _UpdateCheckHostState();
}

class _UpdateCheckHostState extends ConsumerState<UpdateCheckHost>
    with WidgetsBindingObserver {
  Timer? _startupTimer;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startupTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        unawaited(
          ref.read(updateControllerProvider.notifier).runStartupCheck(),
        );
      }
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
    final state = ref.watch(updateControllerProvider);
    final show =
        widget.allowNotices &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        (state.shouldPresentGithubDialog || state.shouldPresentRestartDialog);
    return Column(
      children: [
        if (show)
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.shouldPresentRestartDialog
                            ? '更新已就绪，下次启动生效'
                            : '新版 ${state.githubRelease?.version ?? ""} 可用',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: _opening ? null : () => _open(state),
                      child: const Text('查看'),
                    ),
                    IconButton(
                      tooltip: '稍后提醒',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        final controller = ref.read(
                          updateControllerProvider.notifier,
                        );
                        controller.acknowledgeRestartDialog();
                        if (state.githubRelease case final release?) {
                          final saved = await controller.postponeGithubRelease(
                            release,
                          );
                          if (!saved && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('本次提示已关闭，提醒设置保存失败')),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }

  Future<void> _open(UpdateUiState state) async {
    _opening = true;
    final controller = ref.read(updateControllerProvider.notifier);
    try {
      if (state.shouldPresentRestartDialog && state.snapshot != null) {
        controller.acknowledgeRestartDialog();
        await showUpdateReadyDialog(context, snapshot: state.snapshot!);
      } else if (state.githubRelease != null && state.snapshot != null) {
        controller.acknowledgeGithubDialog();
        await showGithubReleaseDialog(
          context,
          currentVersion: state.snapshot!.appVersion,
          currentBuild: state.snapshot!.buildNumber,
          release: state.githubRelease!,
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
