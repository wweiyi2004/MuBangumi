import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/external_link.dart';
import '../../../core/network/moegirl_service.dart';
import 'subject_expandable_content.dart';

class SubjectMoegirlPanel extends StatelessWidget {
  const SubjectMoegirlPanel({
    super.key,
    required this.entry,
    required this.loading,
    required this.attempted,
    required this.error,
    required this.onLoad,
    required this.onSearch,
    required this.onOpen,
  });

  final MoegirlEntry? entry;
  final bool loading;
  final bool attempted;
  final String? error;
  final VoidCallback onLoad;
  final VoidCallback onSearch;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('补充资料', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (!attempted && !loading)
          OutlinedButton.icon(
            onPressed: onLoad,
            icon: const Icon(Icons.auto_stories_outlined),
            label: const Text('从萌娘百科补充'),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: loading
                ? const Row(
                    children: [
                      SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Expanded(child: Text('正在匹配萌娘百科条目…')),
                    ],
                  )
                : entry != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry!.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SubjectExpandableText(
                        text: entry!.extract,
                        style: theme.textTheme.bodyLarge,
                        collapsedLines: 7,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: onOpen,
                            icon: const Icon(Icons.article_outlined),
                            label: Text(
                              entry!.sections.isEmpty
                                  ? '阅读全文'
                                  : '阅读全文 · ${entry!.sections.length} 章',
                            ),
                          ),
                          Text(
                            '文本来自萌娘百科 · CC BY-NC-SA 3.0 CN',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => unawaited(
                              launchExternalLink(Uri.tryParse(entry!.url)),
                            ),
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('查看原文'),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        error ?? '未找到可信匹配，已避免展示可能错误的条目。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: error == null
                              ? scheme.onSurfaceVariant
                              : scheme.error,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: onLoad,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重试'),
                          ),
                          TextButton.icon(
                            onPressed: onSearch,
                            icon: const Icon(Icons.search_rounded),
                            label: const Text('手动搜索'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}
