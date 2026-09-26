import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'room_connection.dart';
import 'room_comment_preview.dart';
import 'room_comments_sheet.dart';
import 'room_status_chip.dart';
import 'room_summary_view.dart';
import '../../core/theme/app_tokens.dart';

/// Current-round controls stay on the same screen. Lists and historical
/// details live in a drawer; only the content well scrolls for large text.
class ParticipantWorkspace extends StatelessWidget {
  const ParticipantWorkspace({
    super.key,
    required this.controller,
    required this.comment,
    required this.focus,
    required this.score,
    required this.busy,
    required this.onScore,
    required this.onDraft,
    required this.onSubmitScore,
    required this.onSubmitComment,
    this.keyboardVisible = false,
  });
  final ParticipationController controller;
  final TextEditingController comment;
  final FocusNode focus;
  final int? score;
  final bool busy;
  final bool keyboardVisible;
  final ValueChanged<int> onScore;
  final ValueChanged<String> onDraft;
  final VoidCallback onSubmitScore, onSubmitComment;
  @override
  Widget build(BuildContext context) {
    final c = controller, r = c.current;
    final editable =
        r != null && r['status'] == 'open' && c.event?['ended'] != true;
    final keyboard = keyboardVisible;
    final theme = Theme.of(context), colors = theme.colorScheme;
    final pending = c.pending.where((item) => item['round'] == r?['id']).length;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Expanded(
                child: FillBelow(
                  below: keyboard || r == null
                      ? const SizedBox.shrink()
                      : RoomCommentPreview(
                          round: r,
                          onOpenWall: () =>
                              showParticipantDetails(context, tab: 0),
                        ),
                  top: SingleChildScrollView(
                    key: const ValueKey('participant-content'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: c.online ? Colors.green : colors.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${c.name} · ${c.event?['memberCount'] ?? 0} 人已入场',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            Text(
                              c.online ? '实时连接' : '正在重连',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (r == null)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              '主持人正在准备番单，请稍等…',
                              textAlign: TextAlign.center,
                            ),
                          )
                        else ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (!keyboard) ...[
                                ClipRRect(
                                  borderRadius: AppRadius.small,
                                  child: r['subject']['cover'] != ''
                                      ? Image.network(
                                          c.invite!.base
                                              .resolve(
                                                '/cover/${r['subject']['cover']}',
                                              )
                                              .toString(),
                                          width: 54,
                                          height: 76,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => SizedBox(
                                            width: 54,
                                            height: 76,
                                            child: Icon(
                                              Icons.movie_outlined,
                                              color: colors.primary,
                                            ),
                                          ),
                                        )
                                      : Container(
                                          width: 54,
                                          height: 76,
                                          color: colors.primaryContainer,
                                          child: const Icon(
                                            Icons.movie_outlined,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r['subject']['title'],
                                      maxLines: keyboard ? 1 : 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          '第 ${c.rounds.indexOf(r) + 1} / ${c.rounds.length} 轮',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        RoomStatusChip(
                                          status: r['status'],
                                          ended: c.event?['ended'] == true,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (!keyboard) ...[
                            Text('你的评分', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, box) => Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (var n = 1; n <= 10; n++)
                                    SizedBox(
                                      width: (box.maxWidth - 32) / 5,
                                      height: 44,
                                      child: FilledButton.tonal(
                                        style: FilledButton.styleFrom(
                                          minimumSize: Size.zero,
                                          padding: EdgeInsets.zero,
                                          backgroundColor: score == n
                                              ? colors.primary
                                              : colors.surfaceContainer,
                                          foregroundColor: score == n
                                              ? colors.onPrimary
                                              : colors.onSurface,
                                        ),
                                        onPressed: editable
                                            ? () => onScore(n)
                                            : null,
                                        child: Text(
                                          '$n',
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ] else
                            Row(
                              children: [
                                Expanded(child: Text('已选 ${score ?? '—'} 分')),
                                TextButton(
                                  onPressed: focus.unfocus,
                                  child: const Text('修改评分'),
                                ),
                              ],
                            ),
                          const SizedBox(height: 6),
                          Text(
                            '${r['myScore'] == null ? '尚未确认评分' : '已确认评分：${r['myScore']} 分'}${pending > 0 ? ' · $pending 条待确认' : ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (!editable)
                            Text(
                              c.event?['ended'] == true
                                  ? '活动已结束，记录仍可查看'
                                  : '${roomRoundStatus(r['status'])}，目前不能提交',
                              style: theme.textTheme.bodySmall,
                            ),
                          if (c.event?['ended'] == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: FilledButton.tonalIcon(
                                onPressed: () =>
                                    showParticipantDetails(context, tab: 3),
                                icon: const Icon(Icons.leaderboard_outlined),
                                label: const Text('查看整场汇总'),
                              ),
                            ),
                          if (c.message != null)
                            Text(
                              c.message!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.primary,
                              ),
                            ),
                          const SizedBox(height: 10),
                          TextField(
                            key: const ValueKey('participant-comment'),
                            controller: comment,
                            focusNode: focus,
                            enabled: editable,
                            minLines: 2,
                            maxLines: 2,
                            maxLength: 500,
                            onChanged: onDraft,
                            decoration: const InputDecoration(
                              hintText: '写一句感受，匿名发送…',
                              contentPadding: EdgeInsets.all(12),
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '评分与短评匿名展示 · 截止前可修改评分',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: editable && score != null && !busy
                                ? onSubmitScore
                                : null,
                            child: Text(
                              r?['myScore'] == null ? '提交评分' : '更新评分',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: editable && !busy
                                ? onSubmitComment
                                : null,
                            child: const Text('匿名发送'),
                          ),
                        ),
                      ],
                    ),
                    if (!keyboard)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                showParticipantDetails(context, tab: 0),
                            icon: const Icon(Icons.forum_outlined, size: 18),
                            label: const Text('评论墙'),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                showParticipantDetails(context, tab: 1),
                            icon: const Icon(Icons.bar_chart, size: 18),
                            label: const Text('统计'),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                showParticipantDetails(context, tab: 2),
                            icon: const Icon(
                              Icons.view_list_outlined,
                              size: 18,
                            ),
                            label: const Text('番单'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String roomRoundStatus(Object? value) => switch (value) {
  'open' => '评分进行中',
  'waiting' => '等待开始',
  'paused' => '已暂停',
  'closed' => '已截止',
  _ => '等待开始',
};

Future<void> showParticipantDetails(
  BuildContext context, {
  required int tab,
}) async {
  String? selected;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: .82,
      child: StatefulBuilder(
        builder: (context, setState) => Consumer(
          builder: (context, ref, _) {
            final c = ref.watch(participationProvider);
            final selectedEventId = c.event?['id'];
            final r = selected == null
                ? c.current
                : c.rounds.where((v) => v['id'] == selected).firstOrNull;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '番键会现场',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('评论墙')),
                        ButtonSegment(value: 1, label: Text('统计')),
                        ButtonSegment(value: 2, label: Text('番单')),
                        ButtonSegment(value: 3, label: Text('汇总')),
                      ],
                      selected: {tab},
                      onSelectionChanged: (values) =>
                          setState(() => tab = values.first),
                    ),
                    const SizedBox(height: 12),
                    if (selected != null)
                      TextButton(
                        onPressed: () => setState(() => selected = null),
                        child: const Text('返回当前轮次'),
                      ),
                    if (r != null && tab < 2)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          r['subject']['title'],
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        children: [
                          if (tab == 2)
                            for (final item in c.rounds)
                              ListTile(
                                title: Text(item['subject']['title']),
                                subtitle: Text(roomRoundStatus(item['status'])),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => setState(() {
                                  selected = item['id'];
                                  tab = 1;
                                }),
                              ),
                          if (tab == 3) RoomSummaryList(event: c.event),
                          if (tab == 0) ...[
                            if (r?['commentsMore'] == true && c.api != null)
                              TextButton.icon(
                                icon: const Icon(Icons.forum_outlined),
                                label: Text('查看全部 ${r!['commentsTotal']} 条短评'),
                                onPressed: () => showRoomComments(
                                  context,
                                  api: c.api!,
                                  eventId: selectedEventId,
                                  roundId: r['id'],
                                  live: c,
                                  stateKey: () =>
                                      roomCommentsStateKey(c.event, r['id']),
                                  isCurrent: () =>
                                      c.event?['id'] == selectedEventId,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                (r?['commentsOpen'] ?? r?['publicComments']) ==
                                        true
                                    ? '大家的匿名短评'
                                    : '评分后即可查看大家的短评，目前仅展示你自己的评论',
                              ),
                            ),
                            for (final entry in r?['comments'] as List? ?? [])
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person_outline),
                                ),
                                title: Text(
                                  entry['mine'] == true ? '我 · 匿名短评' : '匿名短评',
                                ),
                                subtitle: Text(
                                  '${entry['text']}${entry['hidden'] == true ? '（已隐藏）' : ''}',
                                ),
                              ),
                          ],
                          if (tab == 1) ...[
                            const SizedBox(height: 20),
                            if (r?['stats'] == null)
                              const Text('结果暂未公布，个人分数仅自己可见。')
                            else ...[
                              Text(
                                '${(r!['stats']['mean'] as num?)?.toStringAsFixed(1) ?? '—'} 分',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineLarge,
                              ),
                              Text('${r['count']} 人已评分'),
                              const SizedBox(height: 18),
                              for (var i = 9; i >= 0; i--)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 40,
                                        child: Text('${i + 1} 分'),
                                      ),
                                      Expanded(
                                        child: LinearProgressIndicator(
                                          value:
                                              (r['stats']['distribution'][i]
                                                  as int) /
                                              (r['count'] == 0
                                                  ? 1
                                                  : r['count']),
                                          minHeight: 9,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 30,
                                        child: Text(
                                          '${r['stats']['distribution'][i]}',
                                          textAlign: TextAlign.end,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
