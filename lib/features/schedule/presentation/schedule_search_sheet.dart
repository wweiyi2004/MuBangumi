import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/bangumi_models.dart';
import '../../../models/schedule_models.dart';
import '../../../widgets/subject_widgets.dart';
import '../../../widgets/readable_subject_title.dart';
import '../../../state/app_providers.dart';
import '../../../state/schedule_controller.dart';
import '../application/schedule_search_controller.dart';

Future<void> showScheduleSearchSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => const ScheduleSearchSheet(),
    );

class ScheduleSearchSheet extends ConsumerStatefulWidget {
  const ScheduleSearchSheet({super.key});

  @override
  ConsumerState<ScheduleSearchSheet> createState() =>
      _ScheduleSearchSheetState();
}

class _ScheduleSearchSheetState extends ConsumerState<ScheduleSearchSheet> {
  final _controller = TextEditingController();
  late final ScheduleSearchController _search;
  int? _weekday;
  bool _autoDay = true;

  @override
  void initState() {
    super.initState();
    _search = ScheduleSearchController(api: () => ref.read(bangumiApiProvider));
    _search.addListener(_searchChanged);
    unawaited(_search.loadCalendar());
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  int? _dayFor(Subject subject) =>
      _autoDay ? _search.officialDay(subject.id) : _weekday;

  @override
  void dispose() {
    _search.removeListener(_searchChanged);
    _search.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(Subject subject) async {
    if (_autoDay && _search.calendarLoading) return;
    await ref
        .read(scheduleProvider.notifier)
        .addSubject(subject, weekday: _dayFor(subject));
    // Keep sheet open so multiple titles can be added in one search session.
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(scheduleProvider).schedule;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '搜索 Bangumi 加入新番表',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _search.changeQuery,
              onSubmitted: (_) => unawaited(_search.submit()),
              decoration: InputDecoration(
                hintText: _search.type == SubjectType.anime
                    ? '搜索动画名，例如：迷宫饭'
                    : '搜索${_search.type.label}',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          _search.changeQuery('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('类型', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 8),
                for (final type in const [
                  SubjectType.anime,
                  SubjectType.real,
                ]) ...[
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _search.type == type,
                    onSelected: (_) {
                      unawaited(_search.selectType(type));
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('放到', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('按放送日'),
                  selected: _autoDay,
                  onSelected: (_) => setState(() => _autoDay = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('待安排'),
                  selected: !_autoDay && _weekday == null,
                  onSelected: (_) => setState(() {
                    _autoDay = false;
                    _weekday = null;
                  }),
                ),
                const SizedBox(width: 8),
                for (
                  var day = DateTime.monday;
                  day <= DateTime.sunday;
                  day++
                ) ...[
                  ChoiceChip(
                    label: Text(weekdayLabel(day)),
                    selected: !_autoDay && _weekday == day,
                    onSelected: (_) => setState(() {
                      _autoDay = false;
                      _weekday = day;
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _search.loading
                ? const Center(child: CircularProgressIndicator())
                : _search.error != null
                ? EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: '搜索失败',
                    message: _search.error!,
                    action: FilledButton.tonal(
                      onPressed: _search.submit,
                      child: const Text('重试'),
                    ),
                  )
                : _controller.text.trim().isEmpty
                ? const EmptyState(
                    icon: Icons.search_rounded,
                    title: '搜索作品加入课表',
                    message: '默认按当前官方放送日安排；未收录的放入待安排，也可以手动选择星期。',
                  )
                : _search.results.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: '没有搜索结果',
                    message: '试试更短的关键词，或切换动画/三次元。',
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: _search.results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final subject = _search.results[index];
                      final exists = schedule.containsSubject(subject.id);
                      final day = _dayFor(subject);
                      final waiting = _autoDay && _search.calendarLoading;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        tileColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        leading: SubjectCover(
                          subject: subject,
                          width: 44,
                          height: 62,
                          borderRadius: 8,
                        ),
                        title: ReadableSubjectTitle(
                          subject.displayName,
                          maxLines: 1,
                        ),
                        subtitle: Text(
                          [
                            if (subject.score > 0)
                              subject.score.toStringAsFixed(1),
                            if (subject.date.isNotEmpty) subject.date,
                            if (subject.episodeCount > 0)
                              '${subject.episodeCount} 话',
                          ].join(' · '),
                        ),
                        trailing: exists
                            ? Chip(
                                label: const Text('已在表中'),
                                visualDensity: VisualDensity.compact,
                                side: BorderSide.none,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                              )
                            : FilledButton.tonalIcon(
                                onPressed: waiting
                                    ? null
                                    : () => unawaited(_add(subject)),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: Text(
                                  waiting
                                      ? '查询中'
                                      : day == null
                                      ? '待安排'
                                      : weekdayLabel(day),
                                ),
                              ),
                        onTap: exists || waiting
                            ? null
                            : () => unawaited(_add(subject)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
