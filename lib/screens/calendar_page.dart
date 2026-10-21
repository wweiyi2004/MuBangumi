import '../widgets/content_loading.dart';
import '../core/theme/anime_icon.dart';
import '../navigation/app_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/bangumi_support.dart';
import '../state/session_controller.dart';
import '../widgets/subject_widgets.dart';
import '../widgets/image_share_sheet.dart';
import '../widgets/daily_broadcast_poster.dart';

/// Official Bangumi broadcast calendar (distinct from local 新番表).
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  List<CalendarDay> _days = const [];
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;
  int _selectedWeekday = DateTime.now().weekday;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final days = await ref.read(bangumiApiProvider).getCalendar();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _days = days;
        _loading = false;
        if (days.isNotEmpty &&
            !days.any((d) => d.weekday == _selectedWeekday)) {
          _selectedWeekday = days.first.weekday;
        }
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  CalendarDay? get _selectedDay {
    for (final day in _days) {
      if (day.weekday == _selectedWeekday) return day;
    }
    return _days.isEmpty ? null : _days.first;
  }

  @override
  Widget build(BuildContext context) {
    final day = _selectedDay;
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日放送'),
        actions: [
          IconButton(
            tooltip: '分享当天番剧',
            onPressed: day == null || day.subjects.isEmpty
                ? null
                : () => showImageShareSheet(
                    context,
                    title: '${day.weekdayLabel} · 每日放送',
                    filename: 'MuBangumi-broadcast-${day.weekday}.png',
                    images: [
                      for (final subject in day.subjects)
                        if (subject.imageUrl.isNotEmpty)
                          SubjectCover.imageProvider(
                            subject,
                            width: 60,
                            height: 84,
                            pixelRatio: MediaQuery.devicePixelRatioOf(context),
                          ),
                    ],
                    subtitle: '数据来源：Bangumi 每日放送 · 共 ${day.subjects.length} 部',
                    child: DailyBroadcastPoster(
                      subjects: List.unmodifiable(day.subjects),
                    ),
                  ),
            icon: const AnimeIcon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const AnimeIcon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ContentTransition(
        child: _loading && _days.isEmpty
            ? Column(
                key: const ValueKey('calendar-loading'),
                children: [
                  LoadingStatus(
                    active: true,
                    operation: _loadGeneration,
                    message: '正在加载放送表',
                    onRetry: _load,
                  ),
                  const ContentSkeleton(),
                ],
              )
            : _error != null && _days.isEmpty
            ? EmptyState(
                icon: Icons.cloud_off_outlined,
                title: '放送表加载失败',
                message: _error!,
                action: FilledButton.tonal(
                  onPressed: _load,
                  child: const Text('重试'),
                ),
              )
            : Column(
                key: const ValueKey('calendar-content'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LoadingStatus(
                    active: _loading,
                    operation: _loadGeneration,
                    message: '显示已有放送表，正在更新',
                    onRetry: _load,
                  ),
                  if (_error != null)
                    TextButton(
                      onPressed: _load,
                      child: const Text('更新失败，点击重试'),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      MediaQuery.sizeOf(context).width < 420 ? 12 : 16,
                      8,
                      MediaQuery.sizeOf(context).width < 420 ? 12 : 16,
                      4,
                    ),
                    child: Text(
                      'Bangumi 每日放送',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        for (final d in _days) ...[
                          ChoiceChip(
                            label: Text(
                              '${d.weekdayLabel.isEmpty ? '周${d.weekday}' : d.weekdayLabel}'
                              ' ${d.subjects.length}',
                            ),
                            selected: d.weekday == _selectedWeekday,
                            onSelected: (_) =>
                                setState(() => _selectedWeekday = d.weekday),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: day == null || day.subjects.isEmpty
                        ? const EmptyState(
                            icon: Icons.live_tv_outlined,
                            title: '这天暂无放送',
                            message: '换一天看看，或稍后再刷新。',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: day.subjects.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final subject = day.subjects[index];
                              return SubjectTile(
                                subject: subject,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          SubjectRoute(subject: subject),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
