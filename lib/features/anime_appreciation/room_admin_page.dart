import 'dart:async';
import 'package:banjian_server/banjian_server.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/theme_controller.dart';
import '../../widgets/ascii_refresh.dart';
import 'room_host.dart';

class RoomAdminPage extends ConsumerStatefulWidget {
  const RoomAdminPage({
    super.key,
    required this.subjectPicker,
    required this.onInvite,
    required this.onOpenWeb,
  });
  final WidgetBuilder subjectPicker;
  final Future<void> Function() onInvite, onOpenWeb;
  @override
  ConsumerState<RoomAdminPage> createState() => _RoomAdminPageState();
}

class _RoomAdminPageState extends ConsumerState<RoomAdminPage> {
  final _refresh = GlobalKey<AsciiRefreshState>();
  bool _working = false;
  List<Json> _rounds(Json? e) => ((e?['rounds'] as List?) ?? []).cast<Json>();
  Json? _current(Json? e) =>
      _rounds(e).where((r) => r['id'] == e?['current']).firstOrNull;
  void _message(Object value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value.toString())));
    }
  }

  Future<void> _load() async {
    final host = ref.read(roomHostProvider);
    if (!host.running) throw StateError('活动服务已停止');
    await host.refresh(wait: true);
    if (host.error != null) throw StateError(host.error!);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (e) {
      _message(e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _command(
    String action,
    Json data, {
    required Json expected,
    String? confirm,
  }) => _run(() async {
    final host = ref.read(roomHostProvider);
    bool same() =>
        host.running &&
        host.event?['id'] == expected['id'] &&
        host.event?['version'] == expected['version'];
    if (!same()) {
      _message('活动已变化，请按最新状态重新操作');
      return;
    }
    if (confirm != null && !await _confirm('确认操作', confirm)) return;
    if (!same()) {
      _message('另一位管理员已更新活动，请重新确认');
      return;
    }
    await host.command(action, data);
  });
  Future<void> _name(bool create) async {
    final host = ref.read(roomHostProvider),
        expected = ref.read(roomHostProvider).event;
    var text = create ? '今晚的番键会' : expected?['title'] as String? ?? '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(create ? '创建番键会' : '修改活动名称'),
        content: TextFormField(
          initialValue: text,
          onChanged: (v) => text = v,
          maxLength: 80,
          autofocus: true,
          onFieldSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    if (create) {
      await _run(() => host.command('create', {'title': value}));
    } else if (expected != null) {
      await _command('rename', {'title': value}, expected: expected);
    }
  }

  Future<void> _export(String format) => _run(() async {
    final host = ref.read(roomHostProvider),
        event = ref.read(roomHostProvider).event;
    if (event == null || host.api == null) return;
    final bytes = await host.api!.download(
      'export?event=${event['id']}&format=$format',
    );
    if (!mounted) return;
    final ext = format == 'json' ? 'json' : 'csv';
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出番键会记录',
      fileName: 'banjian-$format-${DateTime.now().millisecondsSinceEpoch}.$ext',
      type: FileType.custom,
      allowedExtensions: [ext],
      bytes: bytes,
      lockParentWindow: true,
    );
    if (result != null) _message('记录已导出（不含姓名与分数对照）');
  });
  Future<void> _menu(String item) async {
    final host = ref.read(roomHostProvider),
        e = ref.read(roomHostProvider).event;
    switch (item) {
      case 'create':
        await _name(true);
      case 'rename':
        await _name(false);
      case 'invite':
        await _run(widget.onInvite);
      case 'web':
        await widget.onOpenWeb();
      case 'history':
        await _details('history');
      case 'members':
        await _details('members');
      case 'playlist':
        await _details('playlist');
      case 'repair':
        if (e != null) {
          await _run(() async {
            await host.api!.request('repair-covers', {'event': e['id']});
            _message('正在后台补齐封面');
          });
        }
      case 'end':
        if (e != null) {
          await _command(
            'end',
            {},
            expected: e,
            confirm: '结束后不能继续评分，已有记录保留。确定结束本次活动？',
          );
        }
      case 'rotate':
        if (e != null) {
          await _command(
            'rotateInvite',
            {},
            expected: e,
            confirm: '更新后旧二维码不能再用于入场，已入场身份保留。确定更新？',
          );
        }
      case 'json':
      case 'scores':
      case 'comments':
        await _export(item);
    }
  }

  Future<void> _details(String kind, {String? roundId}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .86,
        child: Consumer(
          builder: (context, ref, _) {
            final host = ref.watch(roomHostProvider), e = host.event;
            final r = roundId == null
                ? _current(e)
                : _rounds(e).where((v) => v['id'] == roundId).firstOrNull;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            {
                                  'playlist': '番单与顺序',
                                  'members': '入场名单',
                                  'history': '历史活动',
                                  'stats': '评分结果',
                                  'wall': '匿名短评',
                                }[kind] ??
                                '活动详情',
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
                    if (kind == 'members')
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('仅显示提交状态，不展示姓名与分数、评论的对应关系。'),
                      ),
                    Expanded(
                      child: kind == 'playlist'
                          ? _playlist(host, e, expanded: true)
                          : kind == 'wall'
                          ? _comments(e, r)
                          : ListView(
                              children: [
                                if (kind == 'members')
                                  for (final member
                                      in e?['members'] as List? ?? [])
                                    ListTile(
                                      leading: const CircleAvatar(
                                        child: Icon(Icons.person_outline),
                                      ),
                                      title: Text(member['name']),
                                      trailing: Text(
                                        member['submitted'] == true
                                            ? '已评分'
                                            : '未评分',
                                      ),
                                    ),
                                if (kind == 'history')
                                  for (final item in host.history)
                                    ListTile(
                                      title: Text(item['title']),
                                      subtitle: Text(
                                        '${item['ended'] == true ? '已结束' : '进行中'} · ${item['rounds']} 部番剧',
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await _refresh.currentState?.refresh(
                                          task: () => host.refresh(
                                            eventId: item['id'],
                                            wait: true,
                                          ),
                                        );
                                      },
                                    ),
                                if (kind == 'stats')
                                  for (final item
                                      in roundId == null ? _rounds(e) : [?r])
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 24,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['subject']['title'],
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                          _metrics(item, e),
                                          SizedBox(
                                            height: 150,
                                            child: _distribution(item),
                                          ),
                                          const SizedBox(height: 10),
                                          OutlinedButton(
                                            onPressed: e == null
                                                ? null
                                                : () => _command(
                                                    'publish',
                                                    {
                                                      'round': item['id'],
                                                      'value':
                                                          item['published'] !=
                                                          true,
                                                    },
                                                    expected: e,
                                                    confirm:
                                                        item['published'] ==
                                                            true
                                                        ? null
                                                        : '向参与者公布本轮均分和分布？',
                                                  ),
                                            child: Text(
                                              item['published'] == true
                                                  ? '撤回公布'
                                                  : '公布结果',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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
    );
  }

  Widget _panel(String title, Widget child, {Widget? action}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    ),
  );
  Widget _metrics(Json r, Json? e) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        for (final pair in [
          ('均分', (r['stats']?['mean'] as num?)?.toStringAsFixed(1) ?? '—'),
          ('已评分', '${r['count'] ?? 0}'),
          (
            '未评分',
            '${(e?['memberCount'] as int? ?? 0) - (r['count'] as int? ?? 0)}',
          ),
        ])
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(pair.$2, style: Theme.of(context).textTheme.titleLarge),
                  Text(pair.$1, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  Widget _distribution(Json? r) {
    final values =
        ((r?['stats']?['distribution'] as List?) ?? List.filled(10, 0))
            .cast<num>();
    final max = values.fold<num>(1, (a, b) => a > b ? a : b);
    return LayoutBuilder(
      builder: (context, box) {
        final labelHeight = (20 * MediaQuery.textScalerOf(context).scale(1))
            .clamp(10.0, box.maxHeight / 3);
        Widget label(String value) => SizedBox(
          height: labelHeight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: Theme.of(context).textTheme.labelSmall),
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 10; i++)
              Expanded(
                child: Column(
                  children: [
                    label(values[i] > 0 ? '${values[i]}' : ''),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (values[i] / max).toDouble(),
                          child: Container(
                            width: 20,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    label('${i + 1}'),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _playlist(RoomHost host, Json? e, {bool expanded = false}) {
    final rounds = _rounds(e);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (rounds.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('添加几部番剧，开始鉴赏。'),
          ),
        for (final (index, r) in rounds.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              decoration: BoxDecoration(
                color: r['id'] == e?['current']
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: CircleAvatar(
                      radius: 13,
                      child: Text(
                        r['status'] == 'closed' ? '✓' : '${index + 1}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    title: Text(
                      r['subject']['title'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      _status(r['status']),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: r['status'] == 'waiting' && e?['ended'] != true
                        ? TextButton(
                            onPressed: _working
                                ? null
                                : () => _command(
                                    'start',
                                    {'round': r['id']},
                                    expected: e!,
                                    confirm: '开始这部番剧，并截止当前轮次？',
                                  ),
                            child: const Text('开始'),
                          )
                        : IconButton(
                            onPressed: () =>
                                _details('stats', roundId: r['id']),
                            icon: const Icon(Icons.bar_chart, size: 19),
                            tooltip: '查看结果',
                          ),
                  ),
                  if (expanded &&
                      r['status'] == 'waiting' &&
                      e?['ended'] != true)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: '上移',
                          onPressed:
                              _working ||
                                  index == 0 ||
                                  rounds[index - 1]['status'] != 'waiting'
                              ? null
                              : () => _command('move', {
                                  'round': r['id'],
                                  'index': index - 1,
                                }, expected: e!),
                          icon: const Icon(Icons.arrow_upward, size: 18),
                        ),
                        IconButton(
                          tooltip: '下移',
                          onPressed:
                              _working ||
                                  index == rounds.length - 1 ||
                                  rounds[index + 1]['status'] != 'waiting'
                              ? null
                              : () => _command('move', {
                                  'round': r['id'],
                                  'index': index + 1,
                                }, expected: e!),
                          icon: const Icon(Icons.arrow_downward, size: 18),
                        ),
                        TextButton(
                          onPressed: _working
                              ? null
                              : () => _command(
                                  'remove',
                                  {'round': r['id']},
                                  expected: e!,
                                  confirm: '从番单中移除这部尚未开始的番剧？',
                                ),
                          child: const Text('移除'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _comments(Json? e, Json? r) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      if (r == null || (r['comments'] as List).isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Text('等待大家的匿名短评…')),
      for (final c in ((r?['comments'] as List?) ?? []).reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Opacity(
            opacity: c['hidden'] == true ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        c['hidden'] == true ? '匿名短评 · 已隐藏' : '匿名短评',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: _working || e == null
                          ? null
                          : () => _command('hide', {
                              'round': r!['id'],
                              'comment': c['id'],
                              'value': c['hidden'] != true,
                            }, expected: e),
                      child: Text(c['hidden'] == true ? '恢复' : '隐藏'),
                    ),
                  ],
                ),
                Text(c['text']),
                const SizedBox(height: 8),
                const Divider(),
              ],
            ),
          ),
        ),
    ],
  );
  String _status(Object? value) => switch (value) {
    'open' => '评分进行中',
    'paused' => '已暂停',
    'closed' => '已截止',
    _ => '等待开始',
  };
  Widget _pullableCenter(Widget child) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
  Widget _currentPanel(RoomHost host, Json? e, Json? r) {
    if (r == null) {
      return _panel(
        '正在鉴赏',
        _pullableCenter(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_filter_outlined, size: 42),
              const SizedBox(height: 12),
              const Text('从番单选择一部番剧开始'),
              TextButton(
                onPressed: () => _details('playlist'),
                child: const Text('打开番单'),
              ),
            ],
          ),
        ),
      );
    }
    final open = e?['ended'] != true && r['status'] != 'closed';
    final next = _rounds(e).where((v) => v['status'] == 'waiting').firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '正在鉴赏',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  e?['ended'] == true ? '活动已结束' : _status(r['status']),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('admin-current-content'),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child:
                              (r['subject']['cover'] as String? ?? '').isEmpty
                              ? Container(
                                  width: 64,
                                  height: 90,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  child: const Icon(Icons.movie_outlined),
                                )
                              : Image.network(
                                  host.base!
                                      .resolve(
                                        '/cover/${r['subject']['cover']}',
                                      )
                                      .toString(),
                                  width: 64,
                                  height: 90,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const SizedBox(
                                    width: 64,
                                    height: 90,
                                    child: Icon(Icons.movie_outlined),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['subject']['title'],
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '第 ${_rounds(e).indexOf(r) + 1} / ${_rounds(e).length} 轮',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    _metrics(r, e),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                    ),
                    onPressed: !open || _working
                        ? null
                        : () => _command(
                            r['status'] == 'paused' ? 'resume' : 'pause',
                            {'round': r['id']},
                            expected: e!,
                          ),
                    child: Text(r['status'] == 'paused' ? '继续评分' : '暂停评分'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                    ),
                    onPressed: !open || _working
                        ? null
                        : () => _command(
                            'close',
                            {'round': r['id']},
                            expected: e!,
                            confirm: '截止后无法重新开放本轮评分，确认截止？',
                          ),
                    child: const Text('截止本轮'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                    ),
                    onPressed: next == null || e?['ended'] == true || _working
                        ? null
                        : () => _command(
                            'start',
                            {'round': next['id']},
                            expected: e!,
                            confirm: '开始下一部番剧，并截止当前轮次？',
                          ),
                    child: const Text('下一部'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _working
                        ? null
                        : () => _command(
                            'publish',
                            {'round': r['id'], 'value': r['published'] != true},
                            expected: e!,
                            confirm: r['published'] == true
                                ? null
                                : '向参与者公布本轮均分和分布？',
                          ),
                    child: Text(r['published'] == true ? '结果已公布' : '公布结果'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _working
                        ? null
                        : () => _command('comments', {
                            'round': r['id'],
                            'value': r['publicComments'] != true,
                          }, expected: e!),
                    child: Text(
                      r['publicComments'] == true ? '短评墙已开启' : '开放短评墙',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(roomHostProvider), e = host.event;
    final r = _current(e), rounds = _rounds(e);
    final done = rounds.where((r) => r['status'] == 'closed').length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          e?['title'] ?? '番键会管理',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _refresh.currentState?.refresh(),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<ThemeMode>(
            tooltip: '明暗主题',
            icon: const Icon(Icons.brightness_6_outlined),
            onSelected: (mode) =>
                ref.read(themeModeProvider.notifier).setMode(mode),
            itemBuilder: (_) => const [
              PopupMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
              PopupMenuItem(value: ThemeMode.light, child: Text('浅色')),
              PopupMenuItem(value: ThemeMode.dark, child: Text('深色')),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: '管理操作',
            enabled: !_working,
            onSelected: _menu,
            itemBuilder: (_) => [
              if (!host.history.any((v) => v['ended'] != true))
                const PopupMenuItem(value: 'create', child: Text('创建新活动')),
              if (e != null) ...[
                const PopupMenuItem(value: 'rename', child: Text('修改名称')),
                const PopupMenuItem(value: 'playlist', child: Text('番单排序')),
                const PopupMenuItem(value: 'members', child: Text('入场名单')),
                const PopupMenuItem(value: 'repair', child: Text('补全封面')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'scores', child: Text('导出评分 CSV')),
                const PopupMenuItem(value: 'comments', child: Text('导出短评 CSV')),
                const PopupMenuItem(value: 'json', child: Text('导出活动 JSON')),
              ],
              const PopupMenuItem(value: 'history', child: Text('历史活动')),
              const PopupMenuItem(value: 'web', child: Text('浏览器管理入口')),
              if (e != null && e['ended'] != true) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'rotate', child: Text('更新邀请链接')),
                const PopupMenuItem(value: 'end', child: Text('结束活动')),
              ],
            ],
          ),
        ],
      ),
      body: AsciiRefresh(
        key: _refresh,
        onRefresh: _load,
        child: host.running
            ? LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >= 1000;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 1440,
                        maxHeight: 900,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: host.liveConnected
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    '${host.liveConnected ? '实时连接' : '自动同步'} · ${e?['memberCount'] ?? 0} 个参与身份 · ${e?['connections'] ?? 0} 个在线连接',
                                    maxLines: 2,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                                if (e != null && e['ended'] != true) ...[
                                  TextButton.icon(
                                    onPressed: _working
                                        ? null
                                        : () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: widget.subjectPicker,
                                            ),
                                          ),
                                    icon: const Icon(
                                      Icons.playlist_add,
                                      size: 18,
                                    ),
                                    label: const Text('选番'),
                                  ),
                                  TextButton.icon(
                                    onPressed: _working
                                        ? null
                                        : () => _run(widget.onInvite),
                                    icon: const Icon(Icons.qr_code, size: 18),
                                    label: const Text('邀请'),
                                  ),
                                ],
                              ],
                            ),
                            if (host.error != null)
                              Text(
                                host.error!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            if (host.hasPendingCommand)
                              Row(
                                children: [
                                  const Expanded(child: Text('上次操作尚未确认')),
                                  TextButton(
                                    onPressed: () => _run(host.retryCommand),
                                    child: const Text('核对'),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: e == null
                                  ? _pullableCenter(
                                      FilledButton.icon(
                                        onPressed: () => _name(true),
                                        icon: const Icon(Icons.add),
                                        label: const Text('创建番键会'),
                                      ),
                                    )
                                  : wide
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: _panel(
                                            '鉴赏路线',
                                            _playlist(host, e),
                                            action: IconButton(
                                              tooltip: '调整番单',
                                              onPressed: () =>
                                                  _details('playlist'),
                                              icon: const Icon(
                                                Icons.tune,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          flex: 4,
                                          child: Column(
                                            children: [
                                              Expanded(
                                                child: _currentPanel(
                                                  host,
                                                  e,
                                                  r,
                                                ),
                                              ),
                                              if (box.maxHeight >= 640) ...[
                                                const SizedBox(height: 10),
                                                SizedBox(
                                                  height: 136,
                                                  child: _panel(
                                                    '评分分布',
                                                    _distribution(r),
                                                    action: IconButton(
                                                      tooltip: '详细统计',
                                                      onPressed: () =>
                                                          _details('stats'),
                                                      icon: const Icon(
                                                        Icons.open_in_full,
                                                        size: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          flex: 3,
                                          child: _panel(
                                            '匿名短评',
                                            _comments(e, r),
                                          ),
                                        ),
                                      ],
                                    )
                                  : _currentPanel(host, e, r),
                            ),
                            if (e != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    '$done / ${rounds.length} 轮完成',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: rounds.isEmpty
                                          ? 0
                                          : done / rounds.length,
                                      minHeight: 5,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  if (wide)
                                    TextButton(
                                      onPressed: () => _details('members'),
                                      child: const Text('入场名单'),
                                    ),
                                ],
                              ),
                              if (!wide)
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _details('playlist'),
                                      icon: const Icon(
                                        Icons.view_list_outlined,
                                        size: 17,
                                      ),
                                      label: const Text('番单'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _details('stats'),
                                      icon: const Icon(
                                        Icons.bar_chart,
                                        size: 17,
                                      ),
                                      label: const Text('统计'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _details('wall'),
                                      icon: const Icon(
                                        Icons.forum_outlined,
                                        size: 17,
                                      ),
                                      label: const Text('短评'),
                                    ),
                                  ],
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('活动服务已停止，已有记录保留'),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('返回服务设备'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
