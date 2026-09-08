import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/backup/backup_files.dart';
import 'package:mubangumi/screens/backup_page.dart';
import 'package:mubangumi/state/backup_providers.dart';
import 'package:mubangumi/state/session_controller.dart';

import 'support/backup_fixtures.dart';
import 'support/backup_ui_fixtures.dart';
import 'support/ux_visuals.dart';

void main() {
  testWidgets(
    'drafts default off, pending operations remain visible and export saves selected categories',
    (tester) async {
      final env = _Env();
      env.session.useOwner(backupOwner, pending: 3);
      await _show(tester, env);
      expect(find.textContaining('还有 3 项修改待同步'), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const ValueKey('backup-category-privateDrafts')),
      );
      await _tap(tester, find.text('准备备份'));
      expect(
        env.repo.lastExport!.data.containsKey(BackupCategory.privateDrafts),
        true,
      );
      expect(
        env.repo.lastExport!.data.containsKey(BackupCategory.communityDrafts),
        false,
      );
      await _tap(tester, find.text('保存文件'));
      expect(env.files.saved!.checksum, env.repo.lastExport!.checksum);
      expect(env.session.syncCalls, 0);
    },
  );
  testWidgets(
    'cancelled or failed native saving retains the prepared backup for retry',
    (tester) async {
      final env = _Env();
      await _show(tester, env);
      await _tap(tester, find.text('准备备份'));
      env.files.cancelSave = true;
      await _tap(tester, find.text('保存文件'));
      expect(find.textContaining('已取消保存'), findsOneWidget);
      env.files.cancelSave = false;
      env.files.saveError = StateError('full');
      await _tap(tester, find.text('保存文件'));
      expect(find.textContaining('操作未完成'), findsOneWidget);
      env.files.saveError = null;
      await _tap(tester, find.text('保存文件'));
      expect(env.repo.exports, 1);
      expect(env.files.saves, 3);
    },
  );
  testWidgets(
    'import requires preview, preserves unchecked drafts and ignores double execute',
    (tester) async {
      final env = _Env(empty: true);
      await _show(tester, env);
      await _pick(tester);
      expect(env.repo.applies, 0);
      await _tap(tester, find.text('预览导入影响'));
      final gate = Completer<void>();
      env.repo.applyGate = gate.future;
      await _tap(tester, find.text('确认合并所选数据'), settle: false);
      await _tap(tester, find.text('确认合并所选数据'), settle: false);
      await tester.pump();
      expect(env.repo.applies, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(BackupPage), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('本地数据已导入'), findsOneWidget);
      expect(env.repo.local.containsKey(BackupCategory.privateDrafts), false);
      expect(env.repo.local.containsKey(BackupCategory.communityDrafts), false);
      expect(env.session.syncCalls, 0);
    },
  );
  testWidgets(
    'changed preview fails visibly and requires a new preview before retry',
    (tester) async {
      final env = _Env(empty: true);
      await _show(tester, env);
      await _pick(tester);
      await _tap(tester, find.text('覆盖所选类别'));
      await _tap(tester, find.text('预览导入影响'));
      env.repo.local = {
        BackupCategory.pins: [backupPin(999, 0)],
      };
      await _tap(tester, find.text('确认覆盖所选数据'));
      expect(find.textContaining('本地数据在预览后发生了变化'), findsOneWidget);
      expect(find.text('确认覆盖所选数据'), findsNothing);
      expect(env.repo.local[BackupCategory.pins]!.single['subject_id'], 999);
      await _tap(tester, find.text('预览导入影响'));
      await tester.scrollUntilVisible(
        find.textContaining('移除 1'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('移除 1'), findsOneWidget);
      await _tap(tester, find.text('确认覆盖所选数据'));
      expect(find.text('本地数据已导入'), findsOneWidget);
    },
  );
  testWidgets(
    'wrong account or damaged replacement clears the old file instead of reusing it',
    (tester) async {
      final env = _Env();
      await _show(tester, env);
      await _pick(tester);
      env.files.next = PickedBackup(
        'other.json',
        uiBackup(owner: otherBackupOwner),
      );
      await _tap(tester, find.text('更换文件'));
      expect(find.textContaining('备份属于其他账号'), findsOneWidget);
      expect(find.text('预览导入影响'), findsNothing);
      env.files.pickError = const BackupException('备份校验失败');
      await _tap(tester, find.text('选择备份文件'));
      expect(find.text('备份校验失败'), findsOneWidget);
      expect(env.repo.previews, 0);
    },
  );
  for (final stage in ['export', 'pick', 'preview', 'details', 'apply']) {
    testWidgets('account change hides old backup during $stage', (
      tester,
    ) async {
      final env = _Env(empty: true);
      await _show(tester, env);
      final gate = Completer<void>();
      if (stage == 'export') {
        env.repo.exportGate = gate.future;
        await _tap(tester, find.text('准备备份'), settle: false);
      } else {
        if (stage == 'pick') env.files.pickGate = gate.future;
        await _pick(tester, settle: stage != 'pick');
        if (stage != 'pick') {
          if (stage == 'preview') env.repo.previewGate = gate.future;
          await _tap(tester, find.text('预览导入影响'), settle: stage != 'preview');
          if (stage == 'details') {
            await _tap(tester, find.text('查看明细').first);
          } else if (stage == 'apply') {
            env.repo.applyGate = gate.future;
            await _tap(tester, find.text('确认合并所选数据'), settle: false);
          }
        }
      }
      env.session.useOwner(otherBackupOwner);
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('账号已变化'), findsOneWidget);
      expect(find.textContaining('@alice'), findsNothing);
      expect(find.text('保存文件'), findsNothing);
      expect(env.repo.local, isEmpty);
    });
  }
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final dark in [false, true]) {
        testWidgets('backup interface $width scale $scale dark $dark', (
          tester,
        ) async {
          final env = _Env(empty: true);
          await _show(tester, env, width: width, scale: scale, dark: dark);
          final suffix = '${width.toInt()}_${scale}_$dark';
          await captureUx(tester, env.boundary, 'm6_backup_export_$suffix');
          await _tap(tester, find.text('准备备份'));
          await captureUx(tester, env.boundary, 'm6_backup_ready_$suffix');
          await _pick(tester);
          await captureUx(tester, env.boundary, 'm6_backup_select_$suffix');
          await _tap(tester, find.text('覆盖所选类别'));
          await _tap(tester, find.text('预览导入影响'));
          expect(tester.getTopLeft(find.text('核对导入计划')).dy, lessThan(380));
          await captureUx(tester, env.boundary, 'm6_backup_preview_$suffix');
          await _tap(tester, find.text('确认覆盖所选数据'));
          await captureUx(tester, env.boundary, 'm6_backup_result_$suffix');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

class _Env {
  _Env({bool empty = false}) : repo = MemoryBackups(data: empty ? {} : null);
  final MemoryBackups repo;
  final session = BackupUiSession();
  final files = MemoryBackupFiles();
  final boundary = GlobalKey();
}

Future<void> _show(
  WidgetTester tester,
  _Env env, {
  double width = 390,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, width < 500 ? 720 : 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = await uxTheme(tester, dark: dark);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => env.session),
        backupRepositoryProvider.overrideWith((ref) async => env.repo),
        backupFilesProvider.overrideWithValue(env.files),
        backupApplyProvider.overrideWithValue(
          (owner, preview, current) async => BackupApplied(
            changed: await env.repo.apply(
              owner,
              preview,
              isCurrentOwner: current,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: env.boundary, child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BackupPage()),
              ),
              child: const Text('打开备份'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开备份'));
  await tester.pumpAndSettle();
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  final scrollable = find.byType(Scrollable).first;
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pick(WidgetTester tester, {bool settle = true}) async {
  await _tap(tester, find.text('从备份导入'));
  await _tap(tester, find.text('选择备份文件'), settle: settle);
}
