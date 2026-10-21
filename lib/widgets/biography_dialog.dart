import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/anime_icon.dart';
import 'community_rich_content.dart';

Uri? biographyUri(String raw) => communityContentUri(raw);

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

/// Biography syntax follows the website, even when text resembles Markdown.
class BiographyContent extends StatelessWidget {
  const BiographyContent(this.source, {super.key});
  final String source;
  @override
  Widget build(BuildContext context) => CommunityRichContent(source);
}
