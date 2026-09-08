import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bangumi_models.dart';
import '../models/library_batch.dart';
import '../models/schedule_models.dart';
import '../state/library_batch_controller.dart';
import '../state/schedule_controller.dart';
import '../state/session_controller.dart';
import '../widgets/collection_sync_status.dart';

Future<Set<int>?> openLibraryBatchPage(
  BuildContext context, {
  required List<UserCollection> selected,
  required LibraryBatchKind kind,
}) => Navigator.of(context).push<Set<int>>(
  MaterialPageRoute(
    builder: (_) => LibraryBatchPage(selected: selected, kind: kind),
  ),
);

class LibraryBatchPage extends ConsumerStatefulWidget {
  const LibraryBatchPage({
    super.key,
    required this.selected,
    required this.kind,
  });
  final List<UserCollection> selected;
  final LibraryBatchKind kind;
  @override
  ConsumerState<LibraryBatchPage> createState() => _LibraryBatchPageState();
}

class _LibraryBatchPageState extends ConsumerState<LibraryBatchPage> {
  late final SessionController _session;
  late final LibraryBatchAccount? _account;
  ScheduleController? _schedule;
  late SeasonKey _season;
  int? _weekday;
  CollectionType _type = CollectionType.done;
  bool _complete = false,
      _inspecting = false,
      _allowPop = false,
      _closeAfterStop = false;
  int _inspection = 0;
  SeasonSchedule? _target;
  String? _inspectError;
  LibraryBatchController? _runner;
  bool get _sameAccount =>
      _account != null && _session.isCurrentBatchAccount(_account);
  bool get _running => _runner?.running == true;

  @override
  void initState() {
    super.initState();
    _session = ref.read(sessionProvider.notifier);
    _account = _session.batchAccount;
    _season = SeasonKey.current();
    if (widget.kind == LibraryBatchKind.schedule) {
      _schedule = ref.read(scheduleProvider.notifier);
      _season = ref.read(scheduleProvider).season;
      unawaited(_inspect());
    }
    ref.listenManual(sessionProvider, (_, _) {
      if (mounted && !_sameAccount) {
        _runner?.stop();
        setState(() {});
      }
    });
  }

  Future<void> _inspect() async {
    final generation = ++_inspection;
    setState(() {
      _inspecting = true;
      _inspectError = null;
      _target = null;
    });
    try {
      final value = await _schedule!.inspectBatchSeason(_season);
      if (mounted && generation == _inspection) setState(() => _target = value);
    } catch (_) {
      if (mounted && generation == _inspection) {
        setState(() => _inspectError = '无法读取目标季度，请重试');
      }
    } finally {
      if (mounted && generation == _inspection) {
        setState(() => _inspecting = false);
      }
    }
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (_closeAfterStop && !_running) _close();
  }

  void _close() {
    if (_running) {
      _closeAfterStop = true;
      _runner!.stop();
      return;
    }
    if (_allowPop) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, _runner?.completedIds ?? <int>{});
    });
  }

  void _start() {
    if (_runner != null ||
        !_sameAccount ||
        _inspecting ||
        _inspectError != null) {
      return;
    }
    if (widget.kind == LibraryBatchKind.schedule &&
        (_target == null ||
            ref.read(scheduleProvider).loading ||
            ref.read(scheduleProvider).saving)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final plan = LibraryBatchPlan(
      account: _account!,
      kind: widget.kind,
      items: [
        for (final item in widget.selected)
          LibraryBatchItem(
            subject:
                _session.batchCollection(item.subjectId)?.subject ??
                item.subject,
            revision: _session.collectionMutationRevision(item.subjectId),
          ),
      ],
      collectionType: _type,
      completeEpisodes: _type == CollectionType.done && _complete,
      season: _season,
      weekday: _weekday,
    );
    final runner = LibraryBatchController(
      plan,
      AppLibraryBatchBackend(_session, _schedule),
    );
    runner.addListener(_tick);
    setState(() => _runner = runner);
    unawaited(runner.run());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final scheduleBusy =
        widget.kind == LibraryBatchKind.schedule &&
        ref.watch(
          scheduleProvider.select((state) => state.loading || state.saving),
        );
    final current = [
      for (final item in widget.selected)
        session.collectionFor(item.subjectId) ?? item,
    ];
    final active = current
        .where((item) => session.collectionFor(item.subjectId) != null)
        .toList();
    final missing = current.length - active.length;
    final episodeCount = active
        .where((item) => item.subject.type.hasEpisodes)
        .length;
    final unchanged =
        missing +
        (widget.kind == LibraryBatchKind.collection
            ? active
                  .where(
                    (item) =>
                        item.type == _type &&
                        !(_type == CollectionType.done &&
                            _complete &&
                            item.subject.type.hasEpisodes),
                  )
                  .length
            : active
                  .where(
                    (item) => _target?.containsSubject(item.subjectId) == true,
                  )
                  .length);
    final runner = _runner;
    final outcomes = runner?.outcomes ?? const <int, LibraryBatchOutcome>{};
    return PopScope<Set<int>>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _close),
          title: Text(
            widget.kind == LibraryBatchKind.collection ? '批量改状态' : '批量安排',
          ),
        ),
        body: !_sameAccount
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('登录已变化，未开始的项目已停止。已提交的保存会在原操作范围内完成。'),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        Text(
                          '已选 ${widget.selected.length} 部',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text('账号：${session.user?.displayName ?? ''}'),
                        const SizedBox(height: 12),
                        if (runner == null) ...[
                          if (missing > 0) Text('$missing 部已不在收藏中，将跳过'),
                          if (widget.kind == LibraryBatchKind.collection) ...[
                            const Text('目标状态'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final type in CollectionType.values)
                                  ChoiceChip(
                                    label: Text(batchCollectionLabel(type)),
                                    selected: _type == type,
                                    onSelected: (_) =>
                                        setState(() => _type = type),
                                  ),
                              ],
                            ),
                            if (_type == CollectionType.done &&
                                episodeCount > 0)
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _complete,
                                onChanged: (value) =>
                                    setState(() => _complete = value),
                                title: const Text('补齐本篇进度'),
                                subtitle: Text(
                                  '仅动画／三次元（$episodeCount 部），联网后补齐。',
                                ),
                              ),
                            const SizedBox(height: 12),
                            Text(
                              '预计修改 ${current.length - unchanged} 部，$unchanged 部无需修改。评分、吐槽、标签、隐私和书籍进度保持原值。',
                            ),
                          ] else ...[
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: 150,
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _season.year,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: '目标年份',
                                    ),
                                    items: [
                                      for (
                                        var year = 1990;
                                        year <= 2100;
                                        year++
                                      )
                                        DropdownMenuItem(
                                          value: year,
                                          child: Text('$year'),
                                        ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(
                                          () => _season = _season.copyWith(
                                            year: value,
                                          ),
                                        );
                                        unawaited(_inspect());
                                      }
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: 150,
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _season.quarter,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: '目标季度',
                                    ),
                                    items: [
                                      for (var q = 0; q < 4; q++)
                                        DropdownMenuItem(
                                          value: q,
                                          child: Text(
                                            ['冬季', '春季', '夏季', '秋季'][q],
                                          ),
                                        ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(
                                          () => _season = _season.copyWith(
                                            quarter: value,
                                          ),
                                        );
                                        unawaited(_inspect());
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              initialValue: _weekday ?? 0,
                              decoration: const InputDecoration(
                                labelText: '加入位置',
                              ),
                              items: [
                                for (var day = 0; day <= 7; day++)
                                  DropdownMenuItem(
                                    value: day,
                                    child: Text(
                                      day == 0 ? '待安排' : weekdayLabel(day),
                                    ),
                                  ),
                              ],
                              onChanged: (value) => setState(
                                () => _weekday = value == 0 ? null : value,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_inspecting) const LinearProgressIndicator(),
                            if (_inspectError != null) ...[
                              Text(_inspectError!),
                              TextButton(
                                onPressed: _inspect,
                                child: const Text('重试读取'),
                              ),
                            ],
                            if (_target != null)
                              Text(
                                '目标：${_season.label} · ${_weekday == null ? '待安排' : weekdayLabel(_weekday!)}\n预计加入 ${current.length - unchanged} 部，${unchanged - missing} 部已存在并保留原安排。新条目的系统提醒默认关闭。',
                              ),
                          ],
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final type in SubjectType.values)
                                if (current.any(
                                  (item) => item.subject.type == type,
                                ))
                                  Chip(
                                    label: Text(
                                      '${type.label} ${current.where((item) => item.subject.type == type).length}',
                                    ),
                                  ),
                            ],
                          ),
                          ExpansionTile(
                            title: const Text('查看本次作品'),
                            children: [
                              for (final item in current)
                                ListTile(
                                  title: Text(item.subject.displayName),
                                  subtitle: Text(
                                    '${item.subject.type.label} · ${item.type.labelFor(item.subject.type)}',
                                  ),
                                ),
                            ],
                          ),
                        ] else ...[
                          Text(
                            widget.kind == LibraryBatchKind.collection
                                ? '目标：${batchCollectionLabel(runner.plan.collectionType)}${runner.plan.completeEpisodes ? ' · 补齐本篇章节' : ' · 不补齐章节'}'
                                : '目标：${runner.plan.season!.label} · ${runner.plan.weekday == null ? '待安排' : weekdayLabel(runner.plan.weekday!)}',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              Text(
                                '本机已保存 ${runner.count(LibraryBatchStatus.saved)}',
                              ),
                              Text(
                                '未修改 ${runner.count(LibraryBatchStatus.skipped)}',
                              ),
                              Text(
                                '保存失败 ${runner.count(LibraryBatchStatus.failed)}',
                              ),
                              Text(
                                '未开始 ${runner.count(LibraryBatchStatus.notStarted)}',
                              ),
                            ],
                          ),
                          if (runner.running) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                            Text(
                              runner.stopRequested
                                  ? '正在结束当前保存，其余项目不会开始…'
                                  : '正在保存，请稍候…',
                            ),
                          ],
                          if (runner.notice != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(runner.notice!),
                            ),
                          if (widget.kind == LibraryBatchKind.collection) ...[
                            const SizedBox(height: 8),
                            const Text('以下为此账号的全部同步状态（含其他修改）'),
                            const CollectionSyncStatus(),
                          ],
                          const SizedBox(height: 12),
                          for (final item in runner.plan.items)
                            ListTile(
                              title: Text(item.subject.displayName),
                              subtitle: Text(
                                outcomes[item.id]!.message ??
                                    switch (outcomes[item.id]!.status) {
                                      LibraryBatchStatus.notStarted => '未开始',
                                      LibraryBatchStatus.processing => '保存中',
                                      LibraryBatchStatus.saved => '已保存在本机',
                                      LibraryBatchStatus.skipped => '未修改',
                                      LibraryBatchStatus.failed => '保存失败',
                                    },
                              ),
                              leading: Icon(switch (outcomes[item.id]!.status) {
                                LibraryBatchStatus.saved =>
                                  Icons.check_circle_outline,
                                LibraryBatchStatus.failed =>
                                  Icons.error_outline,
                                LibraryBatchStatus.processing =>
                                  Icons.hourglass_top,
                                _ => Icons.remove_circle_outline,
                              }),
                            ),
                        ],
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          if (runner == null) ...[
                            TextButton(
                              onPressed: _close,
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed:
                                  _inspecting ||
                                      _inspectError != null ||
                                      scheduleBusy ||
                                      current.isEmpty
                                  ? null
                                  : _start,
                              child: Text('确认执行（${current.length}）'),
                            ),
                          ] else ...[
                            if (runner.running)
                              TextButton(
                                onPressed: runner.stopRequested
                                    ? null
                                    : runner.stop,
                                child: const Text('停止后续项目'),
                              ),
                            if (!runner.running &&
                                runner.count(LibraryBatchStatus.failed) > 0)
                              FilledButton.tonal(
                                onPressed: () => runner.run(retryFailed: true),
                                child: const Text('仅重试保存失败项'),
                              ),
                            TextButton(
                              onPressed: _close,
                              child: Text(runner.running ? '停止并返回' : '完成'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  void dispose() {
    _inspection++;
    _runner?.removeListener(_tick);
    _runner?.dispose();
    super.dispose();
  }
}
