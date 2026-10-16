import '../core/theme/anime_icon.dart';
import 'image_share_sheet.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/session_controller.dart';

final episodeActivityProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) {
  ref.watch(
    sessionProvider.select(
      (state) => (state.user?.id, state.lastEpisodeEdit?.revision),
    ),
  );
  final result = Completer<Map<String, int>>();
  var disposed = false;
  final timer = Timer(const Duration(seconds: 8), () {
    if (!result.isCompleted) result.completeError(TimeoutException('打卡记录读取超时'));
  });
  ref.onDispose(() {
    disposed = true;
    timer.cancel();
  });
  ref
      .read(sessionProvider.notifier)
      .episodeActivityDays()
      .then<void>(
        (days) {
          timer.cancel();
          if (!disposed && !result.isCompleted) result.complete(days);
        },
        onError: (Object error, StackTrace stack) {
          timer.cancel();
          if (!disposed && !result.isCompleted) {
            result.completeError(error, stack);
          }
        },
      );
  return result.future;
});

String activityDayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class EpisodeActivityHeatmap extends ConsumerStatefulWidget {
  const EpisodeActivityHeatmap({
    super.key,
    this.today,
    this.counts,
    this.expanded = false,
    this.onExpand,
  });
  final DateTime? today;
  final Map<String, int>? counts;
  final bool expanded;
  final VoidCallback? onExpand;
  @override
  ConsumerState<EpisodeActivityHeatmap> createState() =>
      _EpisodeActivityHeatmapState();
}

class _EpisodeActivityHeatmapState
    extends ConsumerState<EpisodeActivityHeatmap> {
  Timer? _dayTimer;
  String? _selected;
  @override
  void initState() {
    super.initState();
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    super.dispose();
  }

  void _openExpanded(BuildContext context, DateTime today) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ExpandedActivityPage(today: today),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.counts == null
        ? ref.watch(episodeActivityProvider)
        : AsyncData(widget.counts!);
    final counts = result.valueOrNull ?? const <String, int>{};
    final now = widget.today ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return Card(
      key: const ValueKey('home-episode-heatmap'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final weeks = ((constraints.maxWidth - 30) / 13).floor().clamp(
              13,
              52,
            );
            const gap = 3.0;
            final cell = ((constraints.maxWidth - 28) / weeks - gap).clamp(
              6.0,
              14.0,
            );
            final endMonday = DateTime(
              today.year,
              today.month,
              today.day - (today.weekday - 1),
            );
            final start = DateTime(
              endMonday.year,
              endMonday.month,
              endMonday.day - (weeks - 1) * 7,
            );
            final total = counts.entries
                .where(
                  (entry) =>
                      entry.key.compareTo(activityDayKey(start)) >= 0 &&
                      entry.key.compareTo(activityDayKey(today)) <= 0,
                )
                .fold<int>(0, (sum, entry) => sum + entry.value);
            Color color(int value) => episodeActivityColor(context, value);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '每日追番',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (!widget.expanded)
                          IconButton(
                            tooltip: '放大每日追番',
                            onPressed:
                                widget.onExpand ??
                                () => _openExpanded(context, today),
                            icon: const AnimeIcon(Icons.open_in_full, size: 20),
                          ),
                      ],
                    ),
                    Text(
                      '今日 ${counts[activityDayKey(today)] ?? 0} 格 · 近 ${DateTime.utc(today.year, today.month, today.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays + 1} 天 $total 格',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Column(
                        children: [
                          for (var day = 0; day < 7; day++)
                            SizedBox(
                              height: cell + gap,
                              child: Center(
                                child: Text(
                                  day == 0
                                      ? '一'
                                      : day == 2
                                      ? '三'
                                      : day == 4
                                      ? '五'
                                      : '',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: gap,
                        children: [
                          for (var week = 0; week < weeks; week++)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var day = 0; day < 7; day++)
                                  Builder(
                                    builder: (_) {
                                      final date = DateTime(
                                        start.year,
                                        start.month,
                                        start.day + week * 7 + day,
                                      );
                                      final key = activityDayKey(date);
                                      final value = counts[key] ?? 0;
                                      final future = date.isAfter(today);
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: gap,
                                        ),
                                        child: Tooltip(
                                          message: future
                                              ? ''
                                              : '$key · $value 格',
                                          child: Semantics(
                                            label: future
                                                ? '未来日期'
                                                : '$key，完成 $value 格',
                                            child: GestureDetector(
                                              onTap: future
                                                  ? null
                                                  : () {
                                                      if (!widget.expanded) {
                                                        _openExpanded(
                                                          context,
                                                          today,
                                                        );
                                                      } else {
                                                        setState(
                                                          () => _selected = key,
                                                        );
                                                      }
                                                    },
                                              child: Container(
                                                width: cell,
                                                height: cell,
                                                decoration: BoxDecoration(
                                                  color: future
                                                      ? Colors.transparent
                                                      : color(value),
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    if (_selected != null)
                      Text(
                        '$_selected · 完成 ${counts[_selected] ?? 0} 格',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('少 ', style: TextStyle(fontSize: 11)),
                        for (final value in [0, 1, 3, 6, 10])
                          Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: color(value),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        const Text(' 多', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ],
                ),
                if (result.hasError)
                  TextButton(
                    onPressed: () => ref.invalidate(episodeActivityProvider),
                    child: const Text('打卡记录暂时无法读取，点击重试'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Color episodeActivityColor(BuildContext context, int value) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (value <= 0) {
    return dark ? const Color(0xFF303644) : const Color(0xFFE6E8ED);
  }
  if (value <= 2) {
    return dark ? const Color(0xFF796128) : const Color(0xFFF5D879);
  }
  if (value <= 5) return const Color(0xFFEE9844);
  if (value <= 9) return const Color(0xFFE45768);
  return dark ? const Color(0xFFFFA3CA) : const Color(0xFF8B2453);
}

class _ExpandedActivityPage extends ConsumerWidget {
  const _ExpandedActivityPage({required this.today});
  final DateTime today;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(episodeActivityProvider);
    final portrait =
        MediaQuery.sizeOf(context).height > MediaQuery.sizeOf(context).width;
    final logicalSize = MediaQuery.sizeOf(context);
    final media = MediaQuery.of(context);
    EdgeInsets rotateInsets(EdgeInsets insets) => portrait
        ? EdgeInsets.fromLTRB(
            insets.top,
            insets.right,
            insets.bottom,
            insets.left,
          )
        : insets;
    return RotatedBox(
      quarterTurns: portrait ? 1 : 0,
      child: MediaQuery(
        data: media.copyWith(
          size: portrait
              ? Size(logicalSize.height, logicalSize.width)
              : logicalSize,
          padding: rotateInsets(media.padding),
          viewPadding: rotateInsets(media.viewPadding),
          viewInsets: rotateInsets(media.viewInsets),
        ),
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.pop(context),
              icon: const AnimeIcon(Icons.arrow_back_rounded),
            ),
            title: const Text('每日追番'),
            actions: [
              IconButton(
                tooltip: '分享每日追番',
                onPressed: result.hasValue
                    ? () => showImageShareSheet(
                        context,
                        title: '每日追番',
                        filename: 'MuBangumi-daily-activity.png',
                        subtitle: '圆格记录每一天的追番足迹 · 最近一年',
                        width: 1040,
                        child: EpisodeActivityHeatmap(
                          today: today,
                          counts: Map.of(result.value!),
                          expanded: true,
                        ),
                      )
                    : null,
                icon: const AnimeIcon(Icons.ios_share_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: EpisodeActivityHeatmap(today: today, expanded: true),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
