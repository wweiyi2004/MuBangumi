import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/bangumi_support.dart';
import '../state/session_controller.dart';
import '../widgets/subject_widgets.dart';
import 'subject_detail_screen.dart';

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
  int _selectedWeekday = DateTime.now().weekday;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final days = await ref.read(bangumiApiProvider).getCalendar();
      if (!mounted) return;
      setState(() {
        _days = days;
        _loading = false;
        if (days.isNotEmpty &&
            !days.any((d) => d.weekday == _selectedWeekday)) {
          _selectedWeekday = days.first.weekday;
        }
      });
    } catch (error) {
      if (!mounted) return;
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
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    MediaQuery.sizeOf(context).width < 420 ? 12 : 16,
                    8,
                    MediaQuery.sizeOf(context).width < 420 ? 12 : 16,
                    4,
                  ),
                  child: Text(
                    MediaQuery.sizeOf(context).width < 420
                        ? '官方放送日历 · 与本地新番表独立'
                        : '官方放送日历 · 与本地「新番表」独立，不会覆盖你的排期',
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
                                    builder: (_) => SubjectDetailScreen(
                                      subject: subject,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
