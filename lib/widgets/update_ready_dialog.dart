import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/external_link.dart';
import '../core/update/app_update_service.dart';

/// Shows the Shorebird "restart to apply" dialog with Markdown release notes.
Future<bool?> showUpdateReadyDialog(
  BuildContext context, {
  required AppUpdateSnapshot snapshot,
}) {
  final markdown = buildUpdateReadyMarkdown(
    appVersion: snapshot.appVersion,
    buildNumber: snapshot.buildNumber,
    nextPatch: snapshot.nextPatch,
    releaseNotesMarkdown: snapshot.releaseNotesMarkdown,
  );
  final allowImmediateExit =
      !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => UpdateReadyDialog(
      markdown: markdown,
      allowImmediateExit: allowImmediateExit,
    ),
  );
}

class UpdateReadyDialog extends StatelessWidget {
  const UpdateReadyDialog({
    super.key,
    required this.markdown,
    this.allowImmediateExit = true,
  });

  final String markdown;
  final bool allowImmediateExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      h2: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      h3: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      p: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
      listBullet: theme.textTheme.bodyMedium,
      strong: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      a: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.primary,
        decoration: TextDecoration.underline,
      ),
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      code: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: scheme.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant, width: 1)),
      ),
    );

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.system_update_alt_rounded),
          SizedBox(width: 10),
          Expanded(child: Text('发现热更新')),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: MarkdownBody(
              data: markdown,
              selectable: true,
              styleSheet: markdownStyle,
              softLineBreak: true,
              onTapLink: (text, href, title) =>
                  unawaited(launchExternalLink(Uri.tryParse(href ?? ''))),
            ),
          ),
        ),
      ),
      actions: [
        if (allowImmediateExit) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('退出并生效'),
          ),
        ] else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('知道了，稍后手动重启'),
          ),
      ],
    );
  }
}
