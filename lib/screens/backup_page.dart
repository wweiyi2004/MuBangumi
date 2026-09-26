import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backup/backup_archive.dart';
import '../core/backup/backup_plan.dart';
import '../models/library_batch.dart';
import '../state/backup_providers.dart';
import '../state/session_controller.dart';
import '../core/theme/app_tokens.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});
  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  late final LibraryBatchAccount? _account;
  bool _importing = false, _busy = false;
  String? _error, _message, _fileName;
  final _exportCategories = {
    for (final category in BackupCategory.values)
      if (!category.isDraft) category,
  };
  Set<BackupCategory> _importCategories = {};
  BackupImportMode _mode = BackupImportMode.merge;
  BackupArchive? _exportReady, _archive;
  BackupPreview? _preview;
  BackupApplied? _applied;
  final _scroll = ScrollController(keepScrollOffset: false);
  int _scrollEpoch = 0;

  @override
  void initState() {
    super.initState();
    _account = ref.read(sessionProvider.notifier).batchAccount;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _current =>
      mounted &&
      _account != null &&
      ref.read(sessionProvider.notifier).isCurrentBatchAccount(_account);
  BackupOwner get _owner => BackupOwner(_account!.userId, _account.username);
  void _toTop() {
    FocusScope.of(context).unfocus();
    // A new step has different children. Recreate the scroll position so the
    // lazy list cannot carry its previous visible child into the new preview.
    setState(() => _scrollEpoch++);
  }

  Future<void> _run(Future<void> Function() work) async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    _toTop();
    try {
      await work();
    } catch (error) {
      if (_current) {
        setState(
          () => _error = error is BackupException
              ? error.message
              : '操作未完成，请检查文件是否可访问、存储空间是否足够，然后重试',
        );
        _toTop();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareExport() => _run(() async {
    final repository = await ref.read(backupRepositoryProvider.future);
    if (!_current) return;
    final archive = await repository.export(_owner, Set.of(_exportCategories));
    if (_current) {
      setState(() => _exportReady = archive);
      _toTop();
    }
  });
  Future<void> _save() => _run(() async {
    final location = await ref.read(backupFilesProvider).save(_exportReady!);
    if (_current) {
      setState(
        () => _message = location == null ? '已取消保存，备份仍可重新保存' : '备份已保存到所选位置',
      );
    }
  });
  Future<void> _share() {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    return _run(() async {
      await ref.read(backupFilesProvider).share(_exportReady!, origin: origin);
      if (_current) setState(() => _message = '已打开系统分享，请以所选应用的结果为准');
    });
  }

  Future<void> _pick() => _run(() async {
    try {
      final picked = await ref.read(backupFilesProvider).pick();
      if (!_current || picked == null) return;
      if (picked.archive.owner.id != _owner.id) {
        throw const BackupException('备份属于其他账号，请先切换到对应账号');
      }
      setState(() {
        _archive = picked.archive;
        _fileName = picked.name;
        _importCategories = picked.archive.data.keys
            .where((category) => !category.isDraft)
            .toSet();
        _preview = null;
        _applied = null;
      });
      _toTop();
    } catch (_) {
      if (_current) {
        setState(() {
          _archive = null;
          _fileName = null;
          _preview = null;
          _applied = null;
          _importCategories = {};
        });
      }
      rethrow;
    }
  });
  Future<void> _makePreview() => _run(() async {
    final repository = await ref.read(backupRepositoryProvider.future);
    if (!_current) return;
    final preview = await repository.preview(
      _owner,
      _archive!,
      Set.of(_importCategories),
      _mode,
    );
    if (_current) {
      setState(() {
        _preview = preview;
        _applied = null;
      });
      _toTop();
    }
  });
  Future<void> _apply() => _run(() async {
    final preview = _preview!;
    try {
      final result = await ref.read(backupApplyProvider)(
        _owner,
        preview,
        () => _current,
      );
      if (_current) {
        setState(() {
          _applied = result;
          _exportReady = null;
        });
        _toTop();
      }
    } catch (_) {
      if (_current) setState(() => _preview = null);
      rethrow;
    }
  });

  void _editImport() {
    _preview = null;
    _applied = null;
    _error = null;
  }

  void _switch(bool importing) {
    if (_busy) return;
    setState(() {
      _importing = importing;
      _error = null;
      _message = null;
    });
    _toTop();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final current = _current;
    return PopScope(
      canPop: !_busy || !current,
      child: Scaffold(
        appBar: AppBar(title: const Text('本地备份')),
        body: !current
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('登录账号已变化，请返回后重新打开备份页面'),
                ),
              )
            : SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: ListView(
                      key: ValueKey(_scrollEpoch),
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          '@${_owner.username} · UID ${_owner.id}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('导出备份'),
                              selected: !_importing,
                              onSelected: _busy ? null : (_) => _switch(false),
                            ),
                            ChoiceChip(
                              label: const Text('从备份导入'),
                              selected: _importing,
                              onSelected: _busy ? null : (_) => _switch(true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_busy) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          const Text('正在处理，请稍候…'),
                          const SizedBox(height: 12),
                        ],
                        if (_error != null) _notice(_error!, error: true),
                        if (_message != null) _notice(_message!),
                        if (_importing)
                          ..._importBody()
                        else
                          ..._exportBody(session.pendingSyncCount),
                        const SizedBox(height: 24),
                        Text(
                          '新番表、RSS、备注与屏蔽是本设备共享设置；其余类别仅属于当前账号。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '备份为明文文件，可能包含私人备注、订阅链接和已选择的草稿，请保存在可信位置。登录凭据、Cookie、缓存与待同步队列不包含在内。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _exportBody(int pending) => [
    _notice(
      pending > 0
          ? '还有 $pending 项修改待同步。备份不包含这些待上传操作，换设备前请先完成同步。'
          : '当前没有待同步修改。备份保存本地安排与偏好；官网收藏和观看进度不包含在此文件中。',
    ),
    if (_exportReady case final archive?) ...[
      Text('备份已准备', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      ..._summary(archive, archive.data.keys.toSet()),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_alt),
            label: const Text('保存文件'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.share_outlined),
            label: const Text('系统分享'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _exportReady = null);
                    _toTop();
                  },
            child: const Text('重新选择类别'),
          ),
        ],
      ),
    ] else ...[
      Text('选择要保存的数据', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final category in BackupCategory.values)
        _category(category, _exportCategories, () {
          _exportReady = null;
        }),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _busy || _exportCategories.isEmpty ? null : _prepareExport,
        icon: const Icon(Icons.inventory_2_outlined),
        label: const Text('准备备份'),
      ),
    ],
  ];

  List<Widget> _importBody() {
    final archive = _archive, preview = _preview, applied = _applied;
    if (applied != null) {
      return [
        Icon(
          applied.changed ? Icons.check_circle_outline : Icons.task_alt,
          size: 44,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          applied.changed ? '本地数据已导入' : '内容一致，无需再次导入',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text('导入没有向 Bangumi 提交收藏或观看进度修改。'),
        if (preview!.categories.contains(BackupCategory.rss))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('RSS 已导入，可前往新番表手动检查更新。'),
          ),
        for (final warning in applied.warnings) _notice(warning, error: true),
        const SizedBox(height: 12),
        Text('本次使用的备份内容', style: Theme.of(context).textTheme.titleMedium),
        ..._summary(archive!, preview.categories),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  setState(_editImport);
                  _toTop();
                },
          child: const Text('返回备份内容'),
        ),
      ];
    }
    if (preview != null) {
      return [
        Text('核对导入计划', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _notice(
          _mode == BackupImportMode.merge
              ? '合并：保留本地冲突项，加入缺少的记录。同季度只追加尚未安排的作品。'
              : '覆盖：所选类别以备份为准，本地多出的记录会移除。请核对下面的数量。',
          error: _mode == BackupImportMode.replace,
        ),
        const Text('未选择的类别保持原样；导入不会自动上传收藏或观看进度。'),
        if (preview.categories.any(
          (category) => const {
            BackupCategory.schedules,
            BackupCategory.rss,
            BackupCategory.people,
          }.contains(category),
        ))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('新番表、RSS、备注与屏蔽属于本设备共享设置，其他账号在这台设备上也会看到修改。'),
          ),
        if (!preview.hasChanges) _notice('所选内容与本地一致，无需修改'),
        for (final category in BackupCategory.values.where(
          preview.categories.contains,
        ))
          _changeCard(preview, category),
        if (preview.skippedSearches > 0)
          _notice('搜索历史最多保留 12 条，本次有 ${preview.skippedSearches} 条未加入。'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _apply,
          icon: const Icon(Icons.download_done),
          label: Text(
            preview.hasChanges
                ? (_mode == BackupImportMode.replace ? '确认覆盖所选数据' : '确认合并所选数据')
                : '核对并完成',
          ),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  setState(_editImport);
                  _toTop();
                },
          child: const Text('修改导入选项'),
        ),
      ];
    }
    return [
      if (archive == null) ...[
        Text('恢复安排与偏好', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('选择 MuBangumi JSON 备份后，先核对账号、类别和冲突，再确认导入。文件上限 16 MB。'),
      ] else ...[
        Text(_fileName!, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('导出于 ${_date(archive.createdAt)}'),
        Text('备份账号 @${archive.owner.username} · UID ${archive.owner.id}'),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy ? null : _pick,
        icon: const Icon(Icons.folder_open),
        label: Text(archive == null ? '选择备份文件' : '更换文件'),
      ),
      if (archive != null) ...[
        const SizedBox(height: 16),
        for (final category in BackupCategory.values.where(
          archive.data.containsKey,
        ))
          _category(
            category,
            _importCategories,
            _editImport,
            detail: _countLabel(category, archive.data[category]!),
          ),
        const SizedBox(height: 16),
        Text('导入方式', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in BackupImportMode.values)
              ChoiceChip(
                label: Text(
                  mode == BackupImportMode.merge ? '合并，保留本地冲突项' : '覆盖所选类别',
                ),
                selected: _mode == mode,
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                        _mode = mode;
                        _editImport();
                      }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy || _importCategories.isEmpty ? null : _makePreview,
          child: const Text('预览导入影响'),
        ),
      ],
    ];
  }

  Widget _category(
    BackupCategory category,
    Set<BackupCategory> selected,
    VoidCallback changed, {
    String? detail,
  }) => CheckboxListTile(
    key: ValueKey('backup-category-${category.name}'),
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(category.label),
    subtitle: category.isDraft || detail != null
        ? Text([?detail, if (category.isDraft) '包含私人文字，默认不选择'].join(' · '))
        : null,
    value: selected.contains(category),
    onChanged: _busy
        ? null
        : (value) => setState(() {
            value == true ? selected.add(category) : selected.remove(category);
            changed();
          }),
  );
  Widget _notice(String message, {bool error = false}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: AppRadius.medium,
    ),
    child: Text(
      message,
      style: TextStyle(
        color: error ? Theme.of(context).colorScheme.onErrorContainer : null,
      ),
    ),
  );
  List<Widget> _summary(
    BackupArchive archive,
    Set<BackupCategory> categories,
  ) => [
    for (final category in BackupCategory.values.where(categories.contains))
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          '${category.label} · ${_countLabel(category, archive.data[category]!)}',
        ),
      ),
  ];
  Widget _changeCard(BackupPreview preview, BackupCategory category) {
    final changes = preview.changes
        .where((change) => change.category == category)
        .toList();
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '备份包含 ${_countLabel(category, preview.archive.data[category]!)}',
            ),
            const SizedBox(height: 6),
            Text(
              changes.isEmpty
                  ? '无需修改'
                  : [
                      for (final kind in BackupChangeKind.values)
                        if (preview.count(category, kind) > 0)
                          '${_changeLabel(kind)} ${preview.count(category, kind)}',
                    ].join(' · '),
            ),
            if (category == BackupCategory.schedules)
              const Text('以上按季度计数，同季度合并保留本地已有作品。'),
            if (changes.isNotEmpty)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _BackupChangesPage(
                            account: _account!,
                            category: category,
                            changes: changes,
                          ),
                        ),
                      ),
                child: const Text('查看明细'),
              ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _countLabel(
  BackupCategory category,
  List<Map<String, dynamic>> rows,
) => switch (category) {
  BackupCategory.schedules =>
    '${rows.length} 个季度 · ${rows.fold<int>(0, (n, row) => n + (row['items'] as List).length)} 部安排',
  BackupCategory.rss =>
    '${rows.where((row) => row['kind'] == 'source').length} 个源 · ${rows.where((row) => row['kind'] == 'binding').length} 条规则',
  _ => '${rows.length} 条',
};
String _changeLabel(BackupChangeKind kind) => switch (kind) {
  BackupChangeKind.added => '新增',
  BackupChangeKind.kept => '冲突保留本地',
  BackupChangeKind.replaced => '替换',
  BackupChangeKind.removed => '移除',
  BackupChangeKind.merged => '合并',
  BackupChangeKind.limited => '未加入',
};

class _BackupChangesPage extends ConsumerWidget {
  const _BackupChangesPage({
    required this.account,
    required this.category,
    required this.changes,
  });
  final LibraryBatchAccount account;
  final BackupCategory category;
  final List<BackupChange> changes;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sessionProvider);
    final current = ref
        .read(sessionProvider.notifier)
        .isCurrentBatchAccount(account);
    return Scaffold(
      appBar: AppBar(title: Text('${category.label}明细')),
      body: !current
          ? const Center(child: Text('账号已变化，请返回'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: changes.length,
              itemBuilder: (_, index) {
                final change = changes[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: SelectableText(change.label),
                  subtitle: Text(_changeLabel(change.kind)),
                );
              },
            ),
    );
  }
}
