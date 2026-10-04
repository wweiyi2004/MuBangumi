import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_tokens.dart';
import '../core/theme/custom_colors.dart';
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
  const EpisodeActivityHeatmap({super.key, this.today});
  final DateTime? today;
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

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(episodeActivityProvider);
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
            Color color(int value) =>
                Theme.of(context).extension<BrandColors>() != null
                ? value <= 0
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : Color.lerp(
                          Theme.of(context).colorScheme.surface,
                          BrandColors.of(context),
                          value <= 2
                              ? .25
                              : value <= 5
                              ? .5
                              : value <= 9
                              ? .75
                              : 1,
                        )!
                : value <= 0
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : value <= 2
                ? const Color(0xFFFBE1E4)
                : value <= 5
                ? const Color(0xFFF5BDC4)
                : value <= 9
                ? AppPalette.bangumiPink
                : AppPalette.roseInk;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('每日追番', style: Theme.of(context).textTheme.titleLarge),
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
                                                  : () => setState(
                                                      () => _selected = key,
                                                    ),
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
