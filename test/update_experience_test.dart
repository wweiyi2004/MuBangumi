import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/update/app_update_service.dart';
import 'package:mubangumi/core/update/github_release.dart';
import 'package:mubangumi/core/update/github_release_store.dart';
import 'package:mubangumi/core/update/update_download.dart';
import 'package:mubangumi/state/update_controller.dart';

const _name = 'MuBangumi-2.2.0-build26-android-arm64-v8a.apk';
const _url =
    'https://github.com/wweiyi2004/MuBangumi/releases/download/v2.2.0+26/$_name';
final _bytes = Uint8List.fromList(List.generate(512, (i) => i % 255));
GithubReleaseAsset _asset({
  String? digest,
  String url = _url,
  String name = _name,
}) => GithubReleaseAsset(
  name: name,
  url: url,
  size: _bytes.length,
  digest: digest ?? 'sha256:${sha256.convert(_bytes)}',
);

void main() {
  test('same version is offered only for an explicit newer logical build', () {
    final release = GithubRelease.fromJson({'tag_name': 'v2.2.0+26'});
    expect(
      shouldOfferGithubRelease(
        currentVersion: '2.2.0',
        currentBuild: '25',
        release: release,
      ),
      isTrue,
    );
    expect(
      shouldOfferGithubRelease(
        currentVersion: '2.2.0',
        currentBuild: '26',
        release: release,
      ),
      isFalse,
    );
    expect(
      shouldOfferGithubRelease(
        currentVersion: '2.3.0',
        currentBuild: '1',
        release: release,
      ),
      isFalse,
    );
    expect(
      () => GithubRelease.fromJson({'tag_name': 'v2.2.0+26-patch.1'}),
      throwsFormatException,
    );
  });

  test(
    'asset matching does not choose incompatible or unverified packages',
    () {
      final asset = _asset();
      final release = GithubRelease(
        tagName: 'v2.2.0+26',
        version: '2.2.0',
        htmlUrl: '',
        assets: [asset],
      );
      expect(
        selectReleaseAsset(
          release,
          platform: 'android',
          androidAbis: ['arm64-v8a'],
        ),
        asset,
      );
      expect(
        selectReleaseAsset(
          release,
          platform: 'android',
          androidAbis: ['x86_64'],
        ),
        isNull,
      );
      expect(selectReleaseAsset(release, platform: 'windows'), isNull);
      expect(
        _asset(
          url: _url.replaceFirst('github.com', 'github.com.evil.test'),
        ).trustedDownload,
        isFalse,
      );
      expect(
        _asset(
          url: _url.replaceFirst('MuBangumi/releases', 'Other/releases'),
        ).trustedDownload,
        isFalse,
      );
      expect(_asset(digest: '').trustedDownload, isFalse);
    },
  );

  test(
    'tomorrow reminder persists across controllers; manual check still offers update',
    () async {
      final store = GithubReleaseSkipStore(memory: {});
      final service = _ReleaseService();
      final first = UpdateController(service, store);
      await first.runStartupCheck();
      expect(first.state.shouldPresentGithubDialog, isTrue);
      await first.postponeGithubRelease(service.release);
      first.dispose();
      final second = UpdateController(service, store);
      await second.runStartupCheck();
      expect(second.state.shouldPresentGithubDialog, isFalse);
      await second.checkNow();
      expect(second.state.githubRelease, service.release);
      second.dispose();
    },
  );

  test(
    'failed GitHub request cannot be reported as latest even if patch is current',
    () async {
      final controller = UpdateController(
        _ReleaseService()..fail = true,
        GithubReleaseSkipStore(memory: {}),
      );
      final state = await controller.checkNow();
      expect(state.phase, AppUpdatePhase.error);
      expect(controller.state.lastError, contains('更新服务'));
      controller.dispose();
    },
  );

  for (final valid in [true, false]) {
    test(
      'download ${valid ? "accepts matching" : "rejects incorrect"} digest and cleans partial files',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'mubangumi-download-test-',
        );
        final dio = Dio()..httpClientAdapter = _Adapter(_bytes);
        final task = UpdateDownload(dio: dio, directory: () async => dir);
        try {
          await task.start(_asset(digest: valid ? null : 'sha256:${'0' * 64}'));
          expect(
            task.phase,
            valid ? UpdateDownloadPhase.ready : UpdateDownloadPhase.error,
          );
          expect(
            await dir.list().where((e) => e.path.endsWith('.partial')).length,
            0,
          );
          if (valid) {
            expect(await task.file!.readAsBytes(), _bytes);
            await task.file!.writeAsString('tampered');
            expect(await task.open(version: '2.2.0'), isFalse);
            expect(task.error, contains('失效'));
          } else {
            expect(await dir.list().length, 0);
          }
        } finally {
          task.dispose();
          await _clean(dir);
        }
      },
    );
  }

  test(
    'cancelled download cannot become ready when a late response arrives',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'mubangumi-download-test-',
      );
      final gate = Completer<void>();
      final dio = Dio()
        ..httpClientAdapter = _Adapter(_bytes, gate: gate.future);
      final task = UpdateDownload(dio: dio, directory: () async => dir);
      try {
        final pending = task.start(_asset());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        task.cancel();
        gate.complete();
        await pending;
        expect(task.phase, UpdateDownloadPhase.idle);
        expect(task.file, isNull);
        expect(await dir.list().length, 0);
      } finally {
        task.dispose();
        await _clean(dir);
      }
    },
  );
}

Future<void> _clean(Directory dir) async {
  if (!dir.absolute.path.startsWith(Directory.systemTemp.absolute.path) ||
      !dir.path.contains('mubangumi-download-test-')) {
    throw StateError('Unexpected cleanup path');
  }
  await dir.delete(recursive: true);
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.bytes, {this.gate});
  final Uint8List bytes;
  final Future<void>? gate;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await gate;
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        'content-length': ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ReleaseService extends AppUpdateService {
  bool fail = false;
  final release = GithubRelease.fromJson({'tag_name': 'v2.2.0+26'});
  @override
  Future<AppUpdateSnapshot> readInstalledVersion() async =>
      const AppUpdateSnapshot(
        phase: AppUpdatePhase.notChecked,
        appVersion: '2.2.0',
        buildNumber: '25',
      );
  @override
  Future<AppUpdateSnapshot> refresh({bool downloadIfOutdated = false}) async =>
      const AppUpdateSnapshot(
        phase: AppUpdatePhase.upToDate,
        appVersion: '2.2.0',
        buildNumber: '25',
      );
  @override
  Future<GithubRelease?> fetchLatestGithubRelease() async {
    if (fail) throw const UpdateCheckException();
    return release;
  }
}
