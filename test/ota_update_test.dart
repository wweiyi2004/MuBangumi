import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/update/app_update_service.dart';
import 'package:mubangumi/core/update/github_release.dart';
import 'package:mubangumi/core/update/github_release_store.dart';
import 'package:mubangumi/state/update_controller.dart';
import 'package:mubangumi/widgets/update_check_host.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

void main() {
  test('version loading never starts a network update check', () async {
    final updater = _Updater()..current = const Patch(number: 2);
    final snapshot = await _service(updater).readInstalledVersion();
    expect(snapshot.phase, AppUpdatePhase.notChecked);
    expect(snapshot.currentPatch, 2);
    expect(updater.checks, 0);
  });

  test(
    'ordinary Flutter builds report unavailable without checking OTA',
    () async {
      final updater = _Updater()..available = false;
      final snapshot = await _service(updater).checkAndDownload();
      expect(snapshot.phase, AppUpdatePhase.unavailable);
      expect(updater.checks, 0);
      expect(updater.downloads, 0);
    },
  );

  test('downloaded patch uses notes for the exact base and patch', () async {
    final updater = _Updater()..status = UpdateStatus.outdated;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(
            Uri.decodeComponent(options.path),
            endsWith('/tags/v2.1.0+10-patch.3'),
          );
          handler.resolve(
            Response(
              requestOptions: options,
              data: <String, dynamic>{'body': '修复本次问题'},
            ),
          );
        },
      ),
    );
    final snapshot = await _service(updater, dio: dio).checkAndDownload();
    expect(updater.downloads, 1);
    expect(snapshot.isRestartReady, isTrue);
    expect(snapshot.nextPatch, 3);
    expect(snapshot.releaseNotesMarkdown, '修复本次问题');
  });

  test('missing patch notes do not hide a ready update', () async {
    final updater = _Updater()..status = UpdateStatus.restartRequired;
    final snapshot = await _service(updater).checkAndDownload();
    expect(snapshot.isRestartReady, isTrue);
    expect(snapshot.releaseNotesMarkdown, isNull);
    expect(updater.downloads, 0);
  });

  test('rollback to base also requires restart', () async {
    final updater = _Updater()
      ..status = UpdateStatus.restartRequired
      ..current = const Patch(number: 3)
      ..next = null;
    final snapshot = await _service(updater).checkAndDownload();
    expect(snapshot.isRestartReady, isTrue);
    expect(snapshot.nextPatch, isNull);
  });

  test('no-op download never falsely announces a pending patch', () async {
    final updater = _Updater()
      ..status = UpdateStatus.outdated
      ..current = const Patch(number: 3);
    final snapshot = await _service(updater).checkAndDownload();
    expect(snapshot.phase, AppUpdatePhase.upToDate);
    expect(snapshot.isRestartReady, isFalse);
  });

  test('download failure is retryable', () async {
    final updater = _Updater()
      ..status = UpdateStatus.outdated
      ..fail = true;
    final service = _service(updater);
    expect((await service.checkAndDownload()).phase, AppUpdatePhase.error);
    updater.fail = false;
    expect((await service.checkAndDownload()).isRestartReady, isTrue);
  });

  test(
    'startup and manual checks share the download and manual caller owns dialog',
    () async {
      final service = _Service();
      final controller = UpdateController(
        service,
        GithubReleaseSkipStore(memory: {}),
      );
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(service.calls, 0);
      final startup = controller.runStartupCheck();
      final manual = controller.checkNow();
      expect(service.calls, 1);
      service.pending.complete(_ready);
      await startup;
      expect((await manual).isRestartReady, isTrue);
      expect(controller.state.shouldPresentRestartDialog, isFalse);
      expect(controller.state.busy, isFalse);
    },
  );

  test('startup prompts once per patch and throttles resume checks', () async {
    final service = _Service();
    final controller = UpdateController(
      service,
      GithubReleaseSkipStore(memory: {}),
    );
    addTearDown(controller.dispose);
    final first = controller.runStartupCheck();
    service.pending.complete(_ready);
    await first;
    expect(controller.state.shouldPresentRestartDialog, isTrue);
    controller.acknowledgeRestartDialog();
    await controller.runStartupCheck();
    expect(service.calls, 1);
    await controller.runStartupCheck(force: true);
    expect(service.calls, 2);
    expect(controller.state.shouldPresentRestartDialog, isFalse);
  });

  test('dispose while checking does not write to disposed state', () async {
    final service = _Service();
    final controller = UpdateController(
      service,
      GithubReleaseSkipStore(memory: {}),
    );
    final operation = controller.checkNow();
    controller.dispose();
    service.pending.complete(_ready);
    expect((await operation).isRestartReady, isTrue);
  });

  testWidgets('OTA runs on a login route and shows one postponable dialog', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateControllerProvider.overrideWith(
            (ref) =>
                UpdateController(service, GithubReleaseSkipStore(memory: {})),
          ),
        ],
        child: const MaterialApp(
          home: UpdateCheckHost(child: Scaffold(body: Text('登录'))),
        ),
      ),
    );
    expect(find.text('登录'), findsOneWidget);
    expect(service.calls, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(service.calls, 1);
    service.pending.complete(_ready);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('登录'), findsOneWidget);
  });
}

AppUpdateService _service(_Updater updater, {Dio? dio}) {
  final client = dio ?? Dio();
  if (dio == null) {
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          );
        },
      ),
    );
  }
  return AppUpdateService(
    updater: updater,
    dio: client,
    packageInfoLoader: () async => PackageInfo(
      appName: 'MuBangumi',
      packageName: 'test',
      version: '2.1.0',
      buildNumber: '10',
    ),
  );
}

class _Updater implements ShorebirdUpdater {
  bool available = true, fail = false;
  int checks = 0, downloads = 0;
  UpdateStatus status = UpdateStatus.upToDate;
  Patch? current;
  Patch? next = const Patch(number: 3);
  @override
  bool get isAvailable => available;
  @override
  Future<Patch?> readCurrentPatch() async => current;
  @override
  Future<Patch?> readNextPatch() async => next;
  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    checks++;
    return status;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    downloads++;
    if (fail) {
      throw const UpdateException(
        message: 'offline',
        reason: UpdateFailureReason.downloadFailed,
      );
    }
  }
}

const _ready = AppUpdateSnapshot(
  phase: AppUpdatePhase.restartRequired,
  appVersion: '2.1.0',
  buildNumber: '10',
  nextPatch: 3,
);

class _Service extends AppUpdateService {
  int calls = 0;
  final pending = Completer<AppUpdateSnapshot>();
  @override
  Future<AppUpdateSnapshot> readInstalledVersion() async =>
      const AppUpdateSnapshot(
        phase: AppUpdatePhase.notChecked,
        appVersion: '2.1.0',
        buildNumber: '10',
      );
  @override
  Future<AppUpdateSnapshot> refresh({bool downloadIfOutdated = false}) {
    calls++;
    return pending.future;
  }

  @override
  Future<GithubRelease?> fetchLatestGithubRelease() async => null;
}
