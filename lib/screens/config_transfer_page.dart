import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/backup/backup_archive.dart';
import '../core/backup/backup_plan.dart';
import '../core/sharing/config_transfer.dart';
import '../core/theme/anime_icon.dart';
import '../models/library_batch.dart';
import '../state/backup_providers.dart';
import '../state/config_transfer_providers.dart';
import '../state/session_controller.dart';
import '../widgets/brand_qr.dart';
import '../widgets/qr_payload_reader.dart';

class ConfigTransferPage extends ConsumerStatefulWidget {
  const ConfigTransferPage({super.key, this.invitation});
  final String? invitation;
  @override
  ConsumerState<ConfigTransferPage> createState() => _ConfigTransferState();
}

class _ConfigTransferState extends ConsumerState<ConfigTransferPage> {
  late final LibraryBatchAccount? _account;
  late final TextEditingController _password;
  final _invitation = TextEditingController();
  final _scroll = ScrollController();
  late final AppLifecycleListener _lifecycle;
  bool _receiving = false,
      _busy = false,
      _obscure = true,
      _appearance = true,
      _friends = true;
  String? _error, _message, _address;
  List<String> _addresses = [];
  Set<BackupCategory> _categories = Set.of(configBackupCategories);
  Uint8List? _encrypted;
  ConfigTransferServer? _server;
  ConfigSnapshot? _snapshot;
  BackupPreview? _preview;
  BackupImportMode _mode = BackupImportMode.merge;
  int _epoch = 0;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    _account = ref.read(sessionProvider.notifier).batchAccount;
    _receiving = widget.invitation != null;
    _password = TextEditingController(
      text: _receiving ? '' : newConfigPassphrase(),
    );
    _invitation.text = widget.invitation ?? '';
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _foreground = false;
        unawaited(_stopServing());
      },
      onResume: () {
        _foreground = true;
      },
      onPause: () {
        _foreground = false;
        unawaited(_stopServing());
      },
    );
    ref.listenManual(sessionProvider.select((s) => (s.user?.id, s.phase)), (
      _,
      _,
    ) {
      if (!_current) {
        _epoch++;
        _encrypted = null;
        _snapshot = null;
        _password.clear();
        unawaited(_stopServing());
      }
    });
    unawaited(_loadAddresses());
  }

  bool get _current =>
      mounted &&
      _account != null &&
      ref.read(sessionProvider.notifier).isCurrentBatchAccount(_account);
  BackupOwner get _owner => BackupOwner(_account!.userId, _account.username);
  @override
  void dispose() {
    _epoch++;
    _lifecycle.dispose();
    unawaited(_server?.close());
    _password.dispose();
    _invitation.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    try {
      final addresses = await ConfigTransferServer.addresses();
      if (mounted) {
        setState(() {
          _addresses = addresses;
          _address = addresses.firstOrNull;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取网络地址，可使用加密文件迁移');
    }
  }

  Future<void> _stopServing() async {
    final server = _server;
    _server = null;
    await server?.close();
    if (mounted) setState(() {});
  }

  void _switch(bool receiving) {
    _epoch++;
    unawaited(_stopServing());
    setState(() {
      _receiving = receiving;
      _encrypted = null;
      _snapshot = null;
      _preview = null;
      _error = _message = null;
      _password.text = receiving ? '' : newConfigPassphrase();
      _categories = Set.of(configBackupCategories);
    });
  }

  Future<void> _run(Future<void> Function(int) action) async {
    if (_busy || !_current) return;
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = _message = null;
    });
    try {
      await action(epoch);
    } catch (error) {
      if (_current && epoch == _epoch) {
        setState(
          () => _error = '$error'
              .replaceFirst('FormatException: ', '')
              .replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _valid(int epoch) => _current && epoch == _epoch;
  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _prepare() => _run((epoch) async {
    final password = _password.text;
    final snapshot = await ref.read(configExportProvider)(
      _account!,
      Set.of(_categories),
    );
    if (!_valid(epoch)) return;
    final encrypted = await compute(encryptConfig, (
      snapshot.toJson(),
      password,
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
    ));
    if (!_valid(epoch)) return;
    setState(() {
      _encrypted = encrypted;
      _obscure = true;
    });
    _toTop();
  });
  Future<void> _serve() => _run((epoch) async {
    await _stopServing();
    final server = await ConfigTransferServer.start(_address!, _encrypted!);
    if (!_valid(epoch) || !_foreground) {
      await server.close();
      return;
    }
    setState(() => _server = server);
    unawaited(
      server.closed.then((_) {
        if (mounted && identical(_server, server)) {
          setState(() {
            _server = null;
            _message = '扫码传输已结束，可重新生成二维码';
          });
        }
      }),
    );
    _toTop();
  });
  Future<void> _saveFile() => _run((epoch) async {
    await FilePicker.platform.saveFile(
      dialogTitle: '保存加密配置',
      fileName: 'MuBangumi-config.muconfig',
      type: FileType.custom,
      allowedExtensions: ['muconfig'],
      bytes: _encrypted!,
      lockParentWindow: true,
    );
  });
  Future<void> _scan() async {
    final raw = await readBangumiQrPayload(context);
    if (!_current || raw == null) return;
    setState(() => _invitation.text = raw);
  }

  Future<void> _receive() => _run((epoch) async {
    final invite = ConfigInvitation.parse(_invitation.text.trim());
    final bytes = await receiveConfig(
      invite,
    ).timeout(const Duration(minutes: 1));
    if (!_valid(epoch)) return;
    await _decode(bytes, epoch);
  });
  Future<void> _pickFile() => _run((epoch) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['muconfig'],
    );
    if (result == null || !_valid(epoch)) return;
    final file = result.files.single;
    if (file.size > configMaxBytes + 60) throw const FormatException('配置文件过大');
    final bytes =
        file.bytes ??
        (file.path == null
            ? Uint8List(0)
            : await File(file.path!).readAsBytes());
    if (!_valid(epoch)) return;
    await _decode(bytes, epoch);
  });
  Future<void> _decode(Uint8List bytes, int epoch) async {
    final json = await compute(decryptConfig, (
      bytes,
      _password.text,
      DateTime.now().millisecondsSinceEpoch,
    ));
    if (!_valid(epoch)) return;
    final snapshot = ConfigSnapshot.fromJson(json);
    if (snapshot.owner.id != _owner.id) {
      throw BackupException('这份配置属于其他账号，请先登录 @${snapshot.owner.username}');
    }
    setState(() {
      _snapshot = snapshot;
      _preview = null;
      _categories = snapshot.backup?.data.keys.toSet() ?? {};
      _appearance = _friends = true;
    });
    _password.clear();
    _toTop();
  }

  Future<void> _makePreview() => _run((epoch) async {
    final archive = _snapshot!.backup;
    final repository = await ref.read(backupRepositoryProvider.future);
    if (!_valid(epoch)) return;
    final preview = archive == null || _categories.isEmpty
        ? null
        : await repository.preview(_owner, archive, Set.of(_categories), _mode);
    if (!_valid(epoch)) return;
    setState(() {
      _preview = preview;
      _message = '已核对导入计划';
    });
    _toTop();
  });
  Future<void> _apply() => _run((epoch) async {
    try {
      final warnings = await ref.read(configApplyProvider)(
        _snapshot!,
        _preview,
        _appearance,
        _friends,
        () => _valid(epoch),
      );
      if (!_valid(epoch)) return;
      setState(() {
        _snapshot = null;
        _preview = null;
        _message =
            '配置迁移完成${warnings.isEmpty ? '' : '\n${warnings.join('\n')}'}';
      });
      _toTop();
    } catch (error) {
      if (_valid(epoch)) setState(() => _preview = null);
      throw StateError('迁移未全部完成，已保存的部分可能已生效。请重新预览后重试。原因：$error');
    }
  });
  @override
  Widget build(BuildContext context) {
    ref.watch(sessionProvider.select((s) => (s.user?.id, s.phase)));
    return PopScope(
      canPop: !_busy || !_current,
      child: Scaffold(
        appBar: AppBar(title: const Text('加密配置迁移')),
        body: !_current
            ? const Center(child: Text('账号已变化，请返回重新打开'))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        '@${_owner.username} · UID ${_owner.id}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('发送配置'),
                            selected: !_receiving,
                            onSelected: _busy ? null : (_) => _switch(false),
                          ),
                          ChoiceChip(
                            label: const Text('接收配置'),
                            selected: _receiving,
                            onSelected: _busy ? null : (_) => _switch(true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_busy) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text('正在处理加密数据，请稍候…'),
                      ],
                      if (_error != null) _notice(_error!, error: true),
                      if (_message != null) _notice(_message!),
                      if (_receiving) ..._receiveBody() else ..._sendBody(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _passwordField({required bool sending}) => TextField(
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: TextInputType.visiblePassword,
    autofillHints: const [],
    controller: _password,
    enabled: !_busy && (!sending || _encrypted == null),
    obscureText: _obscure,
    decoration: InputDecoration(
      labelText: sending ? '传输口令 · 已随机生成' : '输入源设备的传输口令',
      helperText: '至少 12 个字符；口令需单独告诉接收方',
      suffixIcon: IconButton(
        tooltip: _obscure ? '显示口令' : '隐藏口令',
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: AnimeIcon(
          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
  List<Widget> _sendBody() => [
    if (_encrypted == null) ...[
      const Text('外观与好友分组会一起迁移。按需选择其他本地数据；不包含登录凭据、Cookie、草稿、缓存和待同步操作。'),
      const SizedBox(height: 12),
      _passwordField(sending: true),
      for (final c in configBackupCategories)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.label),
          value: _categories.contains(c),
          onChanged: _busy
              ? null
              : (v) => setState(() {
                  if (v == true) {
                    _categories.add(c);
                  } else {
                    _categories.remove(c);
                  }
                }),
        ),
      FilledButton(
        onPressed: _busy ? null : _prepare,
        child: const Text('准备加密配置'),
      ),
    ] else ...[
      _notice(
        '加密配置已准备 · ${(_encrypted!.length / 1024).toStringAsFixed(1)} KB\n同一 Wi-Fi 下扫码接收，发送页面需要保持打开。',
      ),
      _passwordField(sending: true),
      TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: _password.text));
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('口令已复制，请单独传递给接收方')));
          }
        },
        icon: const AnimeIcon(Icons.copy_rounded, size: 18),
        label: const Text('复制传输口令'),
      ),
      if (_addresses.isNotEmpty)
        DropdownButtonFormField<String>(
          borderRadius: BorderRadius.circular(16),
          dropdownColor: Theme.of(context).colorScheme.surface,
          initialValue: _address,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '源设备局域网地址'),
          items: [
            for (final address in _addresses)
              DropdownMenuItem(value: address, child: Text(address)),
          ],
          onChanged: _busy || _server != null
              ? null
              : (v) => setState(() => _address = v),
        ),
      const SizedBox(height: 12),
      if (_server != null) ...[
        Center(child: BrandQr(data: _server!.invitation.qr, size: 280)),
        const SizedBox(height: 8),
        const Text(
          '在另一台设备的「加密配置迁移 → 接收配置」中扫一扫。二维码 10 分钟内有效，口令不包含在二维码中。',
          textAlign: TextAlign.center,
        ),
        TextButton(onPressed: _stopServing, child: const Text('停止扫码传输')),
      ] else if (_address != null)
        FilledButton.icon(
          onPressed: _busy ? null : _serve,
          icon: const AnimeIcon(Icons.qr_code_2_rounded),
          label: const Text('生成传输二维码'),
        )
      else
        _notice('未找到局域网地址，可连接 Wi-Fi 后重试，或保存加密文件。'),
      OutlinedButton.icon(
        onPressed: _busy ? null : _saveFile,
        icon: const AnimeIcon(Icons.save_alt_rounded),
        label: const Text('保存加密文件 · 24 小时内导入'),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () {
                _epoch++;
                unawaited(_stopServing());
                setState(() {
                  _encrypted = null;
                  _password.text = newConfigPassphrase();
                });
              },
        child: const Text('重新选择与加密'),
      ),
    ],
  ];
  List<Widget> _receiveBody() {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return [
        const Text('源设备与接收设备需登录同一 Bangumi 账号。先扫描二维码，再输入单独收到的口令。不同网络可导入加密文件。'),
        const SizedBox(height: 12),
        _passwordField(sending: false),
        const SizedBox(height: 12),
        TextField(
          controller: _invitation,
          enabled: !_busy,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: '配置二维码内容',
            hintText: '扫码或粘贴 mubangumi-config 链接',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const AnimeIcon(Icons.qr_code_scanner_rounded),
              label: const Text('扫一扫 / 从图片识别'),
            ),
            FilledButton(
              onPressed: _busy ? null : _receive,
              child: const Text('接收并解密'),
            ),
            TextButton(
              onPressed: _busy ? null : _pickFile,
              child: const Text('导入加密文件'),
            ),
          ],
        ),
      ];
    }
    final planReady = _message == '已核对导入计划';
    return [
      Text(
        '来自 @${snapshot.owner.username}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text('选择要导入的内容，再预览变化。字体文件与背景图片需在本设备另行导入。'),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('外观与字体选择'),
        subtitle: const Text('应用源设备配色与显示偏好'),
        value: _appearance,
        onChanged: _busy
            ? null
            : (v) => setState(() {
                _appearance = v!;
                _message = null;
              }),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('好友分组'),
        subtitle: Text(
          '${snapshot.groups.names.length} 个分组 · ${snapshot.groups.members.length} 位好友；合并并保留本地已有归属',
        ),
        value: _friends,
        onChanged: _busy
            ? null
            : (v) => setState(() {
                _friends = v!;
                _message = null;
              }),
      ),
      for (final c in snapshot.backup?.data.keys ?? <BackupCategory>[])
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.label),
          subtitle: Text('${snapshot.backup!.data[c]!.length} 条记录'),
          value: _categories.contains(c),
          onChanged: _busy
              ? null
              : (v) => setState(() {
                  if (v == true) {
                    _categories.add(c);
                  } else {
                    _categories.remove(c);
                  }
                  _preview = null;
                  _message = null;
                }),
        ),
      if (snapshot.backup != null)
        Wrap(
          spacing: 8,
          children: [
            for (final mode in BackupImportMode.values)
              ChoiceChip(
                label: Text(
                  mode == BackupImportMode.merge ? '合并，保留本地冲突项' : '覆盖所选本地数据',
                ),
                selected: _mode == mode,
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                        _mode = mode;
                        _preview = null;
                        _message = null;
                      }),
              ),
          ],
        ),
      if (_preview != null) ...[
        const SizedBox(height: 12),
        for (final c in _preview!.categories)
          Text(
            '${c.label}：新增 ${_preview!.count(c, BackupChangeKind.added)} · 保留 ${_preview!.count(c, BackupChangeKind.kept)} · 替换 ${_preview!.count(c, BackupChangeKind.replaced)} · 移除 ${_preview!.count(c, BackupChangeKind.removed)} · 合并 ${_preview!.count(c, BackupChangeKind.merged)}',
          ),
      ],
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _busy || (!_appearance && !_friends && _categories.isEmpty)
            ? null
            : planReady
            ? _apply
            : _makePreview,
        child: Text(
          planReady
              ? (_mode == BackupImportMode.replace && _categories.isNotEmpty
                    ? '确认覆盖所选数据并迁移'
                    : '确认导入所选配置')
              : '预览导入影响',
        ),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                _snapshot = null;
                _preview = null;
                _message = null;
              }),
        child: const Text('取消本次导入'),
      ),
    ];
  }

  Widget _notice(String message, {bool error = false}) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: error ? Theme.of(context).colorScheme.onErrorContainer : null,
      ),
    ),
  );
}
