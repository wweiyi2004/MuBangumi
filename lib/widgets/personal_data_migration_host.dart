import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/storage/sqlite_support.dart';
import 'brand_mark.dart';

/// Resolve portable data once before account providers or stores are created.
class PersonalDataMigrationHost extends StatefulWidget {
  const PersonalDataMigrationHost({
    super.key,
    required this.child,
    this.enabled,
    this.prepare,
  });
  final Widget child;
  final bool? enabled;
  final Future<bool> Function()? prepare;
  @override
  State<PersonalDataMigrationHost> createState() =>
      _PersonalDataMigrationHostState();
}

class _PersonalDataMigrationHostState extends State<PersonalDataMigrationHost> {
  bool _ready = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.enabled ?? Platform.isWindows) {
      _ready = false;
      _busy = true;
      _prepare();
    }
  }

  Future<void> _prepare() async {
    try {
      final ready =
          await (widget.prepare?.call() ?? PersonalDatabasePaths.prepare());
      if (mounted) {
        setState(() {
          _ready = ready;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '旧数据迁移尚未完成。请先退出旧版，再选择旧程序目录重试。';
        });
      }
    }
  }

  Future<void> _choose() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final folder = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择旧版 MuBangumi 程序目录',
        lockParentWindow: true,
      );
      if (folder == null || !mounted) return;
      await PersonalDatabasePaths.migrateFrom(Directory(folder));
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = '未能完成迁移，旧文件已保留。请选择包含旧版数据库的程序目录或 databases 目录后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final accepted = await showDialog<bool>(
        context: _dialogContext!,
        builder: (context) => AlertDialog(
          title: const Text('暂不导入旧目录？'),
          content: const Text(
            '新目录中已有的数据和旧目录文件都会保留。尚未迁移的新番表、草稿和待同步修改不会自动出现，建议先选择旧目录。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回选择'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认继续'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      await PersonalDatabasePaths.startFresh();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = '无法准备用户数据目录，请检查权限后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  BuildContext? _dialogContext;
  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFF09199),
      ),
      home: Builder(
        builder: (context) {
          _dialogContext = context;
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: BrandMark(size: 72)),
                        const SizedBox(height: 24),
                        Text(
                          '把旧数据留在这台电脑',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '新版把个人数据放到系统用户目录，以后更换安装目录也能继续使用。请先退出旧版，再选择旧程序目录；新番表、RSS、偏好、草稿和同步队列会复制过去，旧文件保留。',
                        ),
                        const SizedBox(height: 20),
                        if (_busy)
                          const LinearProgressIndicator()
                        else ...[
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(_error!),
                            ),
                          FilledButton(
                            onPressed: _choose,
                            child: const Text('选择旧程序目录并迁移'),
                          ),
                          TextButton(
                            onPressed: _fresh,
                            child: const Text('这是全新安装／暂不导入'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
