import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/update/github_release.dart';
import 'package:mubangumi/core/update/update_download.dart';
import 'package:mubangumi/core/update/update_source.dart';

final bytes = Uint8List.fromList(List.generate(1024, (i) => i % 251));
const name = 'MuBangumi-2.3.1-build4029-windows-x64.zip';
const url =
    'https://github.com/wweiyi2004/MuBangumi/releases/download/v2.3.1+4029/$name';
const mirror =
    'https://gitee.com/owner/MuBangumi/releases/download/v2.3.1+4029/$name';
GithubReleaseAsset asset({String? mirrorUrl}) => GithubReleaseAsset(
  name: name,
  url: url,
  size: bytes.length,
  digest: 'sha256:${sha256.convert(bytes)}',
  mirrorUrl: mirrorUrl,
  mirrorRepository: 'owner/MuBangumi',
);

ResponseBody full([Uint8List? data]) => ResponseBody.fromBytes(
  data ?? bytes,
  200,
  headers: {
    'content-length': ['${bytes.length}'],
  },
);
ResponseBody rest(int offset, {String? range}) => ResponseBody.fromBytes(
  bytes.sublist(offset),
  206,
  headers: {
    'content-length': ['${bytes.length - offset}'],
    'content-range': [
      range ?? 'bytes $offset-${bytes.length - 1}/${bytes.length}',
    ],
  },
);

void main() {
  late Directory dir;
  late List<UpdateDownload> tasks;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mubangumi-resume-test-');
    tasks = [];
  });
  tearDown(() async {
    for (final task in tasks) {
      task.dispose();
    }
    if (!dir.absolute.path.startsWith(Directory.systemTemp.absolute.path) ||
        !dir.path.contains('mubangumi-resume-test-')) {
      throw StateError('cleanup path');
    }
    await dir.delete(recursive: true);
  });
  UpdateDownload task(
    FutureOr<ResponseBody> Function(RequestOptions) handler, {
    int attempts = 1,
  }) {
    final value = UpdateDownload(
      dio: Dio()..httpClientAdapter = Adapter(handler),
      directory: () async => dir,
      retryDelay: Duration.zero,
      attemptsPerSource: attempts,
    );
    tasks.add(value);
    return value;
  }

  Future<void> seed(int count) async {
    await File(
      '${dir.path}/${asset().sha256Hex}-$name.partial',
    ).writeAsBytes(bytes.sublist(0, count));
  }

  test(
    'transport interruption survives a new downloader and resumes at exact byte',
    () async {
      final first = task(
        (_) => ResponseBody(
          Stream<Uint8List>.fromIterable([bytes.sublist(0, 300)]),
          200,
          headers: {
            'content-length': ['${bytes.length}'],
          },
        ),
      );
      await first.start(asset());
      expect(first.phase, UpdateDownloadPhase.error);
      expect(first.received, 300);
      var calls = 0;
      final second = task((options) {
        calls++;
        expect(options.headers['Range'], 'bytes=300-');
        return rest(300);
      });
      await second.restore(asset());
      expect(second.phase, UpdateDownloadPhase.paused);
      expect(second.received, 300);
      expect(calls, 0);
      await second.start(asset());
      expect(second.phase, UpdateDownloadPhase.ready);
      expect(await second.file!.readAsBytes(), bytes);
    },
  );

  test('automatic retry retains partial bytes', () async {
    var calls = 0;
    final download = task((options) {
      if (calls++ == 0) {
        return ResponseBody.fromBytes(bytes.sublist(0, 200), 200);
      }
      expect(options.headers['Range'], 'bytes=200-');
      return rest(200);
    }, attempts: 2);
    await download.start(asset());
    expect(calls, 2);
    expect(download.phase, UpdateDownloadPhase.ready);
  });

  test('server ignoring Range truncates the old prefix', () async {
    await seed(300);
    final download = task((options) {
      expect(options.headers['Range'], 'bytes=300-');
      return full();
    });
    await download.start(asset());
    expect(download.phase, UpdateDownloadPhase.ready);
    expect(await download.file!.readAsBytes(), bytes);
  });

  for (final range in ['bytes 0-1023/1024', 'bytes 300-1023/9999']) {
    test('rejects mismatched Content-Range: $range', () async {
      await seed(300);
      final download = task((_) => rest(300, range: range));
      await download.start(asset());
      expect(download.phase, UpdateDownloadPhase.error);
      expect(await dir.list().length, 0);
    });
  }

  test('416 discards stale partial and retries from zero', () async {
    await seed(300);
    var calls = 0;
    final download = task((options) {
      if (calls++ == 0) return ResponseBody.fromBytes([], 416);
      expect(options.headers.containsKey('Range'), isFalse);
      return full();
    }, attempts: 2);
    await download.start(asset());
    expect(download.phase, UpdateDownloadPhase.ready);
  });

  test('automatic fallback continues identical bytes from GitHub', () async {
    final hosts = <String>[];
    final download = task((options) {
      hosts.add(options.uri.host);
      if (options.uri.host == 'gitee.com') {
        return ResponseBody.fromBytes(bytes.sublist(0, 400), 200);
      }
      expect(options.headers['Range'], 'bytes=400-');
      return rest(400);
    });
    await download.start(asset(mirrorUrl: mirror));
    expect(hosts, ['gitee.com', 'github.com']);
    expect(download.phase, UpdateDownloadPhase.ready);
  });

  test('explicit source never silently uses the other provider', () async {
    final hosts = <String>[];
    final download = task((options) {
      hosts.add(options.uri.host);
      throw const SocketException('offline');
    });
    await download.start(
      asset(mirrorUrl: mirror),
      source: UpdateSource.domestic,
    );
    expect(hosts, ['gitee.com']);
    hosts.clear();
    await download.start(asset(mirrorUrl: mirror), source: UpdateSource.github);
    expect(hosts, ['github.com']);
  });

  test(
    'mirror ignoring Range preserves the prefix for GitHub fallback',
    () async {
      await seed(300);
      final hosts = <String>[];
      final download = task((options) {
        hosts.add(options.uri.host);
        expect(options.headers['Range'], 'bytes=300-');
        return options.uri.host == 'gitee.com' ? full() : rest(300);
      });
      await download.start(asset(mirrorUrl: mirror));
      expect(hosts, ['gitee.com', 'github.com']);
      expect(download.phase, UpdateDownloadPhase.ready);
      expect(await download.file!.readAsBytes(), bytes);
    },
  );

  test('complete partial is checked locally without network traffic', () async {
    await seed(bytes.length);
    final download = task((_) => throw StateError('must not request'));
    await download.start(asset());
    expect(download.phase, UpdateDownloadPhase.ready);
    final restored = task((_) => throw StateError('must not request'));
    await restored.restore(asset());
    expect(restored.phase, UpdateDownloadPhase.ready);
  });

  test('corrupt completed partial is deleted and downloaded again', () async {
    await seed(bytes.length);
    final partial = File('${dir.path}/${asset().sha256Hex}-$name.partial');
    await partial.writeAsBytes(List.filled(bytes.length, 0));
    final download = task((_) => full(), attempts: 2);
    await download.start(asset());
    expect(download.phase, UpdateDownloadPhase.ready);
    expect(await download.file!.readAsBytes(), bytes);
  });

  test('pause preserves bytes, then cancel deletes them', () async {
    await seed(300);
    final requested = Completer<void>();
    final gate = Completer<void>();
    final download = task((_) async {
      requested.complete();
      await gate.future;
      return rest(300);
    });
    final pending = download.start(asset());
    await requested.future;
    download.pause();
    gate.complete();
    await pending;
    expect(download.phase, UpdateDownloadPhase.paused);
    expect(await dir.list().length, 1);
    expect(download.file, isNull);
    await download.cancel();
    expect(await dir.list().length, 0);
    expect(download.received, 0);
  });
}

class Adapter implements HttpClientAdapter {
  Adapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);
  @override
  void close({bool force = false}) {}
}
