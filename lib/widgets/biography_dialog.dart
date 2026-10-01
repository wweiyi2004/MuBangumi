import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/anime_icon.dart';
import 'community_rich_content.dart';
import 'bounded_image.dart';

Uri? biographyUri(String raw) {
  final uri = Uri.tryParse(raw.startsWith('//') ? 'https:$raw' : raw);
  return uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

class BiographyDialog extends StatelessWidget {
  const BiographyDialog({
    super.key,
    required this.source,
    required this.username,
  });
  final String source, username;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * .82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primaryContainer, scheme.secondaryContainer],
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.surface,
                    child: AnimeIcon(
                      Icons.auto_awesome_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '自我介绍',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: scheme.onPrimaryContainer),
                        ),
                        Text(
                          '@$username',
                          style: TextStyle(color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: AnimeIcon(
                      Icons.close_rounded,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: BiographyContent(source),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: source));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('介绍原文已复制')),
                        );
                      }
                    },
                    icon: const AnimeIcon(Icons.copy_rounded, size: 18),
                    label: const Text('复制原文'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// BBCode-only biographies keep Bangumi's spoiler renderer. Markdown biographies
/// render fenced code, tables and images; BBCode masks stay isolated and folded.
class BiographyContent extends StatelessWidget {
  const BiographyContent(this.source, {super.key});
  final String source;
  @override
  Widget build(BuildContext context) {
    if (!RegExp(
      r'(^|\n)\s*(#{1,6}\s|```|~~~|[-*+]\s|\|)|!\[[^\]]*\]\(|\[[^\]]+\]\(|\*\*|`[^`]+`',
      multiLine: true,
    ).hasMatch(source)) {
      return CommunityRichContent(source);
    }
    final parts = <Widget>[];
    var start = 0;
    // Leave fenced code untouched, including literal BBCode in code examples.
    final blocks = RegExp(
      r'```[^\n]*\n[\s\S]*?```|~~~[^\n]*\n[\s\S]*?~~~|\[(?:mask|spoiler)[^\]]*\][\s\S]*?\[/(?:mask|spoiler)\]',
      caseSensitive: false,
    );
    for (final match in blocks.allMatches(source)) {
      if (match.start > start) {
        parts.add(_markdown(context, source.substring(start, match.start)));
      }
      final block = match.group(0)!;
      parts.add(
        block.startsWith('[')
            ? CommunityRichContent(block)
            : _markdown(context, block, convert: false),
      );
      start = match.end;
    }
    if (start < source.length) {
      parts.add(_markdown(context, source.substring(start)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: parts,
    );
  }

  Widget _markdown(BuildContext context, String text, {bool convert = true}) {
    final scheme = Theme.of(context).colorScheme;
    if (convert) {
      for (final pair in [('b', '**'), ('i', '*'), ('s', '~~')]) {
        text = text.replaceAll(
          RegExp('\\[/?${pair.$1}\\]', caseSensitive: false),
          pair.$2,
        );
      }
      text = text
          .replaceAllMapped(
            RegExp(r'\[img\]([^\[]+)\[/img\]', caseSensitive: false),
            (m) => '![](${m[1]})',
          )
          .replaceAllMapped(
            RegExp(r'\[url=([^\]]+)\]([\s\S]*?)\[/url\]', caseSensitive: false),
            (m) => '[${m[2]}](${m[1]})',
          );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MarkdownBody(
        data: text,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: Theme.of(context).textTheme.bodyLarge,
          code: TextStyle(
            fontFamily: 'monospace',
            color: scheme.onSurface,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
          codeblockDecoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          codeblockPadding: const EdgeInsets.all(14),
          blockquoteDecoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: .35),
            border: Border(left: BorderSide(width: 3, color: scheme.primary)),
          ),
        ),
        onTapLink: (_, href, _) async {
          final uri = biographyUri(href ?? '');
          if (uri == null) return;
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        },
        imageBuilder: (uri, title, alt) {
          final safe = biographyUri(uri.toString());
          if (safe == null) return const Text('（无效图片链接）');
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: Image(
                image: boundedImageProvider(
                  NetworkImage(safe.toString()),
                  width: MediaQuery.sizeOf(context).width,
                  height: 400,
                  pixelRatio: MediaQuery.devicePixelRatioOf(context),
                ),
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        height: 90,
                        color: scheme.surfaceContainer,
                        child: const Center(child: Text('图片加载中…')),
                      ),
                errorBuilder: (_, _, _) =>
                    Text('图片加载失败${alt?.isNotEmpty == true ? '：$alt' : ''}'),
              ),
            ),
          );
        },
      ),
    );
  }
}
