import 'package:flutter/material.dart';

import '../models/episode_edit.dart';
import '../state/session_controller.dart';

void showEpisodeUndoMessage(
  BuildContext context,
  SessionController controller,
  EpisodeUndo undo, {
  String? message,
}) {
  if (!identical(controller.pendingEpisodeUndo, undo)) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentSnackBar();
  final action = SnackBarAction(
    label: '撤销',
    onPressed: () async {
      final error = await controller.undoEpisode(undo);
      if (!context.mounted) return;
      if (error != null && identical(controller.pendingEpisodeUndo, undo)) {
        showEpisodeUndoMessage(
          context,
          controller,
          undo,
          message: '撤销未保存：$error，可以重试',
        );
      } else {
        messenger.showSnackBar(SnackBar(content: Text(error ?? '已恢复原章节状态')));
      }
    },
  );
  final stacked =
      MediaQuery.sizeOf(context).width < 500 &&
      MediaQuery.textScalerOf(context).scale(14) > 18;
  final bar = messenger.showSnackBar(
    SnackBar(
      content: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message ?? undo.message),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    action,
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => messenger.hideCurrentSnackBar(
                        reason: SnackBarClosedReason.dismiss,
                      ),
                      icon: Icon(
                        Icons.close,
                        color: Theme.of(context).colorScheme.onInverseSurface,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Text(message ?? undo.message),
      duration: const Duration(seconds: 10),
      persist: MediaQuery.accessibleNavigationOf(context),
      showCloseIcon: !stacked,
      action: stacked ? null : action,
    ),
  );
  bar.closed.then((reason) {
    if (reason != SnackBarClosedReason.action) {
      controller.dismissEpisodeUndo(undo);
    }
  });
}
