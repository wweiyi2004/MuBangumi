import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/layout/app_layout.dart';
import '../core/network/moegirl_service.dart';

class MoegirlDetailScreen extends StatelessWidget {
  const MoegirlDetailScreen({super.key, required this.entry});

  final MoegirlEntry entry;

  Future<void> _openOriginal() async {
    final uri = Uri.tryParse(entry.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '在萌娘百科打开',
            onPressed: () => unawaited(_openOriginal()),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SelectionArea(
        child: ListView(
          padding: AppLayout.pageInsets(context, top: 12, bottom: 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card.filled(
                      margin: EdgeInsets.zero,
                      color: scheme.secondaryContainer.withValues(alpha: 0.55),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.auto_stories_rounded,
                              color: scheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '萌娘百科补充资料',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${entry.sections.length} 个可读章节 · '
                                    '文本已转换为 MuBangumi 原生界面',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (entry.extract.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('导语', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 10),
                      Card.outlined(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            entry.extract,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.65,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (entry.sections.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text('正文', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 10),
                      for (
                        var index = 0;
                        index < entry.sections.length;
                        index++
                      )
                        _NativeSectionCard(
                          section: entry.sections[index],
                          initiallyExpanded: index < 2,
                        ),
                    ],
                    const SizedBox(height: 22),
                    Card.outlined(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Text(
                              '文本来自萌娘百科，默认采用 CC BY-NC-SA 3.0 CN。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => unawaited(_openOriginal()),
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('查看原文与完整版权信息'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NativeSectionCard extends StatelessWidget {
  const _NativeSectionCard({
    required this.section,
    required this.initiallyExpanded,
  });

  final MoegirlSection section;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nested = section.level > 2;
    return Padding(
      padding: EdgeInsets.only(left: nested ? 12 : 0, bottom: 8),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          maintainState: true,
          leading: Icon(
            nested
                ? Icons.subdirectory_arrow_right_rounded
                : Icons.notes_rounded,
            color: scheme.primary,
          ),
          title: Text(
            section.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: nested ? FontWeight.w600 : FontWeight.w800,
            ),
          ),
          children: [
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  section.body,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.65),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
