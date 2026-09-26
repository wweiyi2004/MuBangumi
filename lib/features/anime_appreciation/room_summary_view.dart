import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/material.dart';

/// The whole-activity ranking. Participants see every played round once the
/// activity ends; before that only rounds the host published.
class RoomSummaryList extends StatelessWidget {
  const RoomSummaryList({super.key, required this.event, this.host = false});
  final Json? event;
  final bool host;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final entries = roomSummary(event);
    final ended = event?['ended'] == true;
    final rated = entries.fold<int>(0, (n, e) => n + e.count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            ended
                ? '按均分排名 · 共 ${entries.length} 部 · $rated 次评分'
                : host
                ? '活动结束后，参与者会看到这份汇总'
                : '目前只包含主持人已公布的轮次，活动结束后公布全部',
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('还没有可以汇总的评分', textAlign: TextAlign.center),
          ),
        for (final e in entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: e.rank <= 3
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              foregroundColor: e.rank <= 3
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
              child: Text('${e.rank}'),
            ),
            title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${e.count} 人评分${e.myScore == null ? '' : ' · 我打了 ${e.myScore} 分'}',
            ),
            trailing: Text(
              e.mean.toStringAsFixed(1),
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.primary,
              ),
            ),
          ),
      ],
    );
  }
}
