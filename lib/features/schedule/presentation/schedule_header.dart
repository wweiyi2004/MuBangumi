import 'package:flutter/material.dart';
import '../../../models/schedule_models.dart';

class ScheduleSeasonPicker extends StatelessWidget {
  const ScheduleSeasonPicker({
    super.key,
    required this.season,
    required this.currentSeason,
    required this.compact,
    required this.knownSeasons,
    required this.onChanged,
    required this.onCreate,
    this.onDeleteCurrent,
    this.onPick,
  });

  final SeasonKey season;
  final SeasonKey currentSeason;
  final bool compact;
  final List<SeasonKey> knownSeasons;
  final ValueChanged<SeasonKey> onChanged;
  final VoidCallback onCreate;
  final VoidCallback? onDeleteCurrent;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    // Nearby seasons as quick picks + anything the user has created/opened.
    final now = currentSeason;
    final quick = <SeasonKey>[];
    var cursor = now.quarter == 0
        ? SeasonKey(year: now.year - 1, quarter: 3)
        : SeasonKey(year: now.year, quarter: now.quarter - 1);
    for (var i = 0; i < 6; i++) {
      quick.add(cursor);
      cursor = cursor.quarter == 3
          ? SeasonKey(year: cursor.year + 1, quarter: 0)
          : SeasonKey(year: cursor.year, quarter: cursor.quarter + 1);
    }
    final map = <String, SeasonKey>{
      for (final key in [...quick, ...knownSeasons, season]) key.id: key,
    };
    final list = map.values.toList()
      ..sort((a, b) {
        final byYear = b.year.compareTo(a.year);
        if (byYear != 0) return byYear;
        return b.quarter.compareTo(a.quarter);
      });

    list.remove(season);
    list.insert(0, season);
    if (compact) {
      return Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<SeasonKey>(
              key: ValueKey('season-dropdown-${season.id}'),
              initialValue: season,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '季度',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: [
                for (final option in list)
                  DropdownMenuItem(
                    value: option,
                    child: Text(
                      option.label.replaceFirst('新番', ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (option) {
                if (option != null) onChanged(option);
              },
            ),
          ),
          Tooltip(
            message: '挑选本季新番',
            child: TextButton(onPressed: onPick, child: const Text('选番')),
          ),
          PopupMenuButton<String>(
            tooltip: '季度操作',
            onSelected: (action) {
              if (action == 'create') {
                onCreate();
              } else {
                onDeleteCurrent?.call();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'create', child: Text('新建表')),
              if (onDeleteCurrent != null)
                const PopupMenuItem(value: 'delete', child: Text('删空表')),
            ],
          ),
        ],
      );
    }
    return SingleChildScrollView(
      key: ValueKey('season-shortcuts-${season.id}'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新建表'),
            onPressed: onCreate,
          ),
          const SizedBox(width: 8),
          for (final option in list) ...[
            ChoiceChip(
              label: Text(option.label),
              selected: option == season,
              onSelected: (_) => onChanged(option),
            ),
            const SizedBox(width: 8),
          ],
          if (onDeleteCurrent != null) ...[
            ActionChip(
              avatar: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              label: Text(
                '删空表',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: onDeleteCurrent,
            ),
          ],
        ],
      ),
    );
  }
}

class ScheduleToolbar extends StatelessWidget {
  const ScheduleToolbar({
    super.key,
    required this.wide,
    required this.refreshing,
    required this.unread,
    required this.onExport,
    required this.onUpdates,
    required this.onRefresh,
    required this.onSources,
  });
  final bool wide, refreshing;
  final int unread;
  final VoidCallback onExport, onUpdates, onRefresh, onSources;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (Navigator.canPop(context))
        IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      Expanded(
        child: Text(
          '新番表',
          style: wide
              ? Theme.of(context).textTheme.headlineLarge
              : Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      if (wide)
        IconButton(
          tooltip: '导出图片',
          onPressed: onExport,
          icon: const Icon(Icons.image_outlined),
        ),
      IconButton(
        tooltip: '更新提醒',
        onPressed: onUpdates,
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: const Icon(Icons.notifications_outlined),
        ),
      ),
      if (wide) ...[
        IconButton(
          tooltip: refreshing ? '检查中…' : '检查更新',
          onPressed: refreshing ? null : onRefresh,
          icon: refreshing
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded),
        ),
        IconButton(
          tooltip: '更新源 RSS',
          onPressed: onSources,
          icon: const Icon(Icons.rss_feed_rounded),
        ),
      ] else
        PopupMenuButton<String>(
          tooltip: '新番表更多操作',
          onSelected: (action) {
            switch (action) {
              case 'export':
                onExport();
              case 'refresh':
                onRefresh();
              case 'sources':
                onSources();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'export', child: Text('导出图片')),
            PopupMenuItem(
              value: 'refresh',
              enabled: !refreshing,
              child: Text(refreshing ? '检查中…' : '检查更新'),
            ),
            const PopupMenuItem(value: 'sources', child: Text('更新源 RSS')),
          ],
        ),
    ],
  );
}
