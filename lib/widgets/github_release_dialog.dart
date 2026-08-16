import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/external_link.dart';
import '../core/update/github_release.dart';

enum GithubReleaseDialogResult { skip, later, download }

Future<GithubReleaseDialogResult?> showGithubReleaseDialog(
  BuildContext context, {
  required String currentVersion,
  required String currentBuild,
  required GithubRelease release,
}) {
  return showDialog<GithubReleaseDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => GithubReleaseDialog(
      markdown: buildGithubReleaseMarkdown(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        release: release,
      ),
      downloadUrl: release.htmlUrl,
    ),
  );
}

class GithubReleaseDialog extends StatelessWidget {
  const GithubReleaseDialog({
    super.key,
    required this.markdown,
    this.downloadUrl,
  });

  final String markdown;
  final String? downloadUrl;

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
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
    );

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.new_releases_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('发现新版本')),
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
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(GithubReleaseDialogResult.skip),
          child: const Text('跳过此版本'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(GithubReleaseDialogResult.later),
          child: const Text('稍后'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await launchExternalLink(Uri.tryParse(downloadUrl ?? ''));
            if (context.mounted) {
              Navigator.of(context).pop(GithubReleaseDialogResult.download);
            }
          },
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('前往下载'),
        ),
      ],
    );
  }
}
