// Alternative QA entrypoint. Never imported by lib/main.dart or release builds.
// Uses synthetic accounts and isolated databases; no Bangumi requests or login.
import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/backup/backup_files.dart';
import 'package:mubangumi/core/backup/backup_plan.dart';
import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/screens/backup_page.dart';
import 'package:mubangumi/state/backup_providers.dart';
import 'package:mubangumi/state/rss_controller.dart';
import 'package:mubangumi/state/schedule_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/user_preferences_controller.dart';

import '../../test/support/backup_fixtures.dart';
import '../../test/support/backup_ui_fixtures.dart';
import '../../test/support/schedule_fixtures.dart';

SemanticsHandle? _semantics;
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _semantics = SemanticsBinding.instance.ensureSemantics();
  runApp(const NativeBackupProbe());
}

class NativeBackupProbe extends StatefulWidget {
  const NativeBackupProbe({super.key});
  @override
  State<NativeBackupProbe> createState() => _NativeBackupProbeState();
}

class _NativeBackupProbeState extends State<NativeBackupProbe> {
  final report = <String, Object?>{
    'platform': Platform.operatingSystem,
    'probe_revision': 3,
  };
  Directory? directory;
  BackupTestStores? source, target;
  BackupArchive? archive;
  bool busy = true;
  String status = '正在初始化原生存储…';
  final session = BackupUiSession();
  ProviderContainer? container;
  final navigator = GlobalKey<NavigatorState>();
  final boundary = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      developer.registerExtension('ext.mubangumi.qa', (
        method,
        parameters,
      ) async {
        final action = parameters['action'];
        if (action == 'save' || action == 'pick') {
          if (busy || archive == null) {
            return developer.ServiceExtensionResponse.error(
              -32000,
              'Probe is busy',
            );
          }
          unawaited(_fileAction(action == 'save'));
        } else if (action == 'open') {
          if (busy || container == null) {
            return developer.ServiceExtensionResponse.error(
              -32000,
              'Probe is not ready',
            );
          }
          navigator.currentState?.push(
            MaterialPageRoute<void>(builder: (_) => _backupPage()),
          );
        } else if (action == 'screenshot') {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await File(
            path.join(
              directory!.path,
              '${Platform.operatingSystem}-screen.png',
            ),
          ).writeAsBytes(bytes!.buffer.asUint8List());
        } else if (action != 'report') {
          return developer.ServiceExtensionResponse.error(
            -32000,
            'Unknown QA action',
          );
        }
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'busy': busy, 'report': report}),
        );
      });
    }
    _initialize();
  }

  Future<void> _record(String message) async {
    status = message;
    report['status'] = message;
    report['time_utc'] = DateTime.now().toUtc().toIso8601String();
    if (directory != null) {
      await File(
        path.join(directory!.path, '${Platform.operatingSystem}-report.json'),
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
    }
    if (mounted) setState(() {});
    debugPrint('MUBANGUMI_QA: $message');
  }

  Future<void> _initialize() async {
    try {
      const configured = String.fromEnvironment('QA_OUTPUT');
      final root = configured.isNotEmpty
          ? configured
          : path.join(
              (Platform.isAndroid
                      ? await getExternalStorageDirectory()
                      : await getTemporaryDirectory())!
                  .path,
              'MuBangumi-QA',
            );
      directory = await Directory(root).create(recursive: true);
      final dataRoot = Platform.isAndroid
          ? path.join(
              (await getApplicationSupportDirectory()).path,
              'native-backup-qa',
            )
          : root;
      await Directory(dataRoot).create(recursive: true);
      report['database_root'] = dataRoot;
      source = BackupTestStores(
        await Directory(path.join(dataRoot, 'source')).create(recursive: true),
      );
      target = BackupTestStores(
        await Directory(path.join(dataRoot, 'target')).create(recursive: true),
      );
      final seeded = File(path.join(dataRoot, 'seeded'));
      if (!await seeded.exists()) {
        await source!.seed();
        await seeded.writeAsString('synthetic data only', flush: true);
      }
      archive = await source!.repository().export(
        backupOwner,
        allBackupCategories,
      );
      await File(
        path.join(root, '${Platform.operatingSystem}-export.json'),
      ).writeAsBytes(archive!.encode(), flush: true);
      final expected = File(path.join(root, 'expected.json'));
      if (await expected.exists()) {
        final previous = BackupArchive.decode(await expected.readAsBytes());
        final restored = await target!.repository().export(
          backupOwner,
          allBackupCategories,
        );
        if (backupRowsDigest(previous.data, allBackupCategories) !=
            backupRowsDigest(restored.data, allBackupCategories)) {
          throw StateError(
            'Process restart did not preserve the last imported data',
          );
        }
        report['process_restart_verified'] = true;
      } else {
        await _importAndVerify(archive!);
        report['native_roundtrip_verified'] = true;
      }
      report['export_path'] = path.join(
        root,
        '${Platform.operatingSystem}-export.json',
      );
      report['database_count'] = 6;
      report['category_count'] = archive!.data.length;
      await _record('原生存储校验通过 · 8 类数据');
    } catch (error, stack) {
      report['error'] = '$error';
      report['stack'] = '$stack';
      await _record('原生校验失败：$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _importAndVerify(BackupArchive input) async {
    final watch = Stopwatch()..start();
    final repo = target!.repository();
    final preview = await repo.preview(
      backupOwner,
      input,
      allBackupCategories,
      BackupImportMode.replace,
    );
    final changed = await repo.apply(
      backupOwner,
      preview,
      isCurrentOwner: () => true,
    );
    await target!.close();
    final restored = await target!.repository().export(
      backupOwner,
      allBackupCategories,
    );
    final digest = backupRowsDigest(input.data, allBackupCategories);
    if (backupRowsDigest(restored.data, allBackupCategories) != digest) {
      throw StateError('Native import contents differ');
    }
    await File(
      path.join(directory!.path, 'expected.json'),
    ).writeAsBytes(restored.encode(), flush: true);
    report['last_import'] = {
      'checksum': input.checksum,
      'data_digest': digest,
      'changed': changed,
      'elapsed_ms': watch.elapsedMilliseconds,
    };
    report['bangumi_sync_calls'] = session.syncCalls;
  }

  Future<void> _fileAction(bool saving) async {
    if (busy || archive == null) return;
    setState(() => busy = true);
    try {
      final files = PlatformBackupFiles();
      if (saving) {
        final saved = await files.save(archive!);
        report['native_saved_path'] = saved;
        await _record(saved == null ? '已取消原生保存' : '原生文件保存完成');
      } else {
        final picked = await files.pick();
        if (picked == null) {
          await _record('已取消原生选择');
          return;
        }
        await _importAndVerify(picked.archive);
        report['native_picked_name'] = picked.name;
        report['cross_file_verified'] = true;
        await _record('原生文件选择与导入校验通过');
      }
    } catch (error) {
      report['error'] = '$error';
      await _record('文件校验失败：$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = target;
    final page = MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) =>
          RepaintBoundary(key: boundary, child: child!),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('原生备份验收')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('仅使用合成账号和隔离数据库', style: TextStyle(fontSize: 22)),
              const SizedBox(height: 16),
              Text(status),
              if (busy) const LinearProgressIndicator(),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy || archive == null
                    ? null
                    : () => _fileAction(true),
                child: const Text('保存原生导出文件'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy || archive == null
                    ? null
                    : () => _fileAction(false),
                child: const Text('选择文件并导入校验'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: busy || data == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => _backupPage()),
                      ),
                child: const Text('打开应用备份页面'),
              ),
              const SizedBox(height: 16),
              SelectableText(directory?.path ?? ''),
            ],
          ),
        ),
      ),
    );
    if (data == null) return page;
    container ??= ProviderContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => session),
        backupRepositoryProvider.overrideWith((ref) async => data.repository()),
        browsingRepositoryProvider.overrideWithValue(data.browsing),
        homePinsRepositoryProvider.overrideWithValue(data.browsing),
        scheduleViewRepositoryProvider.overrideWithValue(data.browsing),
        recommendationFeedbackRepositoryProvider.overrideWithValue(
          data.browsing,
        ),
        scheduleStoreProvider.overrideWithValue(data.schedules),
        rssStoreProvider.overrideWithValue(data.rss),
        scheduleReminderProvider.overrideWithValue(MemoryScheduleReminders()),
        userPreferencesProvider.overrideWith(
          (ref) => UserPreferencesController(data.people),
        ),
      ],
    );
    return page;
  }

  Widget _backupPage() => UncontrolledProviderScope(
    container: container!,
    child: const BackupPage(),
  );

  @override
  void dispose() {
    container?.dispose();
    _semantics?.dispose();
    super.dispose();
  }
}
