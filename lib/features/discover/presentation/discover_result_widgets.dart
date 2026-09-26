import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/network/bangumi_endpoints.dart';
import '../../../widgets/subject_widgets.dart';
import '../domain/discover_query.dart';

class EmptyDiscoverState extends StatelessWidget {
  const EmptyDiscoverState({
    super.key,
    required this.searching,
    required this.resultLabel,
    required this.activeFilterCount,
    required this.keyword,
    required this.onClearFilters,
    required this.onClearSearch,
    required this.onOpenFilters,
  });

  final bool searching;
  final String resultLabel;
  final int activeFilterCount;
  final String keyword;
  final VoidCallback onClearFilters;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final title = searching ? '没有找到相关$resultLabel' : '这里暂时没有内容';
    final message = searching
        ? activeFilterCount > 0
              ? keyword.isEmpty
                    ? '当前标签与筛选条件没有结果。可清除筛选后重试。'
                    : '关键词「$keyword」在当前筛选下没有结果。可清除筛选，或换更短关键词。'
              : '关键词「$keyword」没有匹配的$resultLabel。试试换类型，或缩短关键词。'
        : '当前浏览条件下没有条目，试试换年份/季度，或直接搜索作品名。';

    return SizedBox(
      width: double.infinity,
      child: EmptyState(
        icon: Icons.search_off_rounded,
        scene: ProjectionScene.discover,
        title: title,
        message: message,
        action: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            if (searching && activeFilterCount > 0)
              FilledButton.tonalIcon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('清除筛选'),
              ),
            if (searching)
              FilledButton.tonalIcon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.clear_rounded),
                label: const Text('清空搜索'),
              ),
            if (!searching && activeFilterCount > 0)
              FilledButton.tonalIcon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('重置浏览条件'),
              ),
            if (!searching || activeFilterCount > 0)
              OutlinedButton.icon(
                onPressed: onOpenFilters,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('调整筛选'),
              ),
          ],
        ),
      ),
    );
  }
}

class DiscoverSearchPrompt extends StatelessWidget {
  const DiscoverSearchPrompt({super.key, required this.target});

  final DiscoverSearchTarget target;

  @override
  Widget build(BuildContext context) {
    final label = target == DiscoverSearchTarget.character ? '角色' : '人物';
    final example = target == DiscoverSearchTarget.character ? '鲁路修' : '福山润';
    return SizedBox(
      width: double.infinity,
      child: EmptyState(
        icon: target == DiscoverSearchTarget.character
            ? Icons.face_retouching_natural_rounded
            : Icons.person_search_rounded,
        title: '输入$label名开始搜索',
        message: '例如：$example。这里不会混入条目季度榜。',
      ),
    );
  }
}

class DiscoverMonoThumb extends StatelessWidget {
  const DiscoverMonoThumb({super.key, required this.url, this.round = false});

  final String url;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = url.isEmpty
        ? ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Icon(
              round ? Icons.person_rounded : Icons.face_rounded,
              size: 20,
            ),
          )
        : CachedNetworkImage(
            imageUrl: BangumiEndpoints.imageUrl(
              url,
              size: BangumiImageSize.grid,
            ),
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            memCacheWidth: 88,
            memCacheHeight: 120,
            errorWidget: (_, _, _) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined, size: 18),
            ),
          );
    if (round) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: scheme.surfaceContainerHighest,
        child: ClipOval(child: SizedBox(width: 44, height: 44, child: child)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 44, height: 60, child: child),
    );
  }
}
