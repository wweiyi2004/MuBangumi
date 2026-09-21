import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'github_release.dart';
import 'update_source.dart';

const updatePlatformChannel = MethodChannel('mubangumi/updates');

Future<String> logicalUpdateBuild(String fallback) async {
  if (!Platform.isAndroid) return fallback;
  try {
    return await updatePlatformChannel.invokeMethod<String>('buildNumber') ??
        fallback;
  } catch (_) {
    return fallback;
  }
}

Future<GithubReleaseAsset?> deviceReleaseAsset(GithubRelease release) async {
  if (Platform.isWindows) {
    return selectReleaseAsset(release, platform: 'windows');
  }
  if (!Platform.isAndroid) return null;
  try {
    final abis =
        await updatePlatformChannel.invokeListMethod<String>('abis') ?? [];
    return selectReleaseAsset(release, platform: 'android', androidAbis: abis);
  } catch (_) {
    return null;
  }
}

enum UpdateDownloadPhase { idle, downloading, paused, verifying, ready, error }

class _ResumeUnsupported implements Exception {}

final updateDownloadProvider = Provider<UpdateDownload>((ref) {
  final download = UpdateDownload();
  ref.onDispose(download.dispose);
  return download;
});

class UpdateDownload extends ChangeNotifier {
  UpdateDownload({
    Dio? dio,
    Future<Directory> Function()? directory,
    this.retryDelay = const Duration(milliseconds: 500),
    this.attemptsPerSource = 2,
  }) : assert(attemptsPerSource > 0),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
             ),
           ),
       _directory =
           directory ??
           (() async => Directory(
             p.join(
               (await getApplicationSupportDirectory()).path,
               'mubangumi-updates',
             ),
           ));

  final Dio _dio;
  final Future<Directory> Function() _directory;
  final Duration retryDelay;
  final int attemptsPerSource;
  UpdateDownloadPhase phase = UpdateDownloadPhase.idle;
  GithubReleaseAsset? asset;
  GithubRelease? release;
  File? file;
  String? error;
  int received = 0;
  CancelToken? _cancel;
  bool _running = false, _deleteOnStop = false;
  File? _partial, _completed;
  String? activeSource;
  bool _disposed = false;
  DateTime? _lastProgress;
  bool get busy => _running;
  double? get progress =>
      asset == null ? null : (received / asset!.size).clamp(0, 1);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Restores a saved download without starting network traffic.
  Future<void> restore(GithubReleaseAsset next) async {
    if (busy || _disposed || !next.trustedDownload) return;
    _running = true;
    try {
      await _prepare(next);
      if (await _validFile(_completed!, next)) {
        file = _completed;
        received = next.size;
        phase = UpdateDownloadPhase.ready;
      } else {
        received = await _partial!.exists() ? await _partial!.length() : 0;
        if (received > next.size) {
          await _discard(_partial);
          received = 0;
        }
        phase = received > 0
            ? UpdateDownloadPhase.paused
            : UpdateDownloadPhase.idle;
      }
    } catch (_) {
      phase = UpdateDownloadPhase.idle;
    } finally {
      _running = false;
      _notify();
    }
  }

  Future<void> _prepare(GithubReleaseAsset next) async {
    asset = next;
    file = null;
    error = null;
    final directory = await _directory();
    await directory.create(recursive: true);
    final stem = '${next.sha256Hex}-${next.name}';
    _partial = File(p.join(directory.path, '$stem.partial'));
    _completed = File(p.join(directory.path, stem));
  }

  Future<void> start(
    GithubReleaseAsset next, {
    UpdateSource source = UpdateSource.auto,
  }) async {
    if (busy || _disposed) return;
    if (!next.trustedDownload) {
      error = '安装包缺少有效校验信息，请前往发布页下载';
      phase = UpdateDownloadPhase.error;
      _notify();
      return;
    }
    final token = _cancel = CancelToken();
    _running = true;
    _deleteOnStop = false;
    asset = next;
    file = null;
    error = null;
    received = 0;
    phase = UpdateDownloadPhase.downloading;
    _notify();
    try {
      await _prepare(next);
      _checkStopped(token);
      if (await _validFile(_completed!, next)) {
        _checkStopped(token);
        file = _completed;
        received = next.size;
        phase = UpdateDownloadPhase.ready;
        return;
      }
      await _discard(_completed);
      final urls = <String>[
        if (source != UpdateSource.github && next.trustedMirrorUrl != null)
          next.trustedMirrorUrl!,
        if (source != UpdateSource.domestic) next.url,
      ];
      if (urls.isEmpty) throw StateError('domestic source unavailable');
      Object? lastError;
      for (final url in urls) {
        activeSource = url == next.url ? 'GitHub' : '国内源（Gitee）';
        for (var attempt = 0; attempt < attemptsPerSource; attempt++) {
          _checkStopped(token);
          phase = UpdateDownloadPhase.downloading;
          _notify();
          try {
            await _receive(
              next,
              url,
              token,
              preserveResume: source == UpdateSource.auto && url != urls.last,
            );
            _checkStopped(token);
            phase = UpdateDownloadPhase.verifying;
            _notify();
            if (!await _validFile(_partial!, next)) {
              throw const FormatException('digest');
            }
            _checkStopped(token);
            await _partial!.rename(_completed!.path);
            _checkStopped(token);
            file = _completed;
            phase = UpdateDownloadPhase.ready;
            return;
          } catch (e) {
            _checkStopped(token);
            lastError = e;
            // Keep the existing bytes for the next source, instead of replacing
            // them with a complete response from a mirror that ignores Range.
            if (e is _ResumeUnsupported) break;
            if (e is FormatException) {
              await _discard(_partial);
              received = 0;
            }
            if (attempt + 1 < attemptsPerSource) {
              await Future.any([
                Future<void>.delayed(retryDelay),
                token.whenCancel,
              ]);
            }
          }
        }
      }
      throw lastError ?? StateError('download unavailable');
    } catch (e) {
      if (!token.isCancelled && !_disposed) {
        error = e is FormatException ? '安装包校验失败，请重新下载' : '下载未完成，已保留进度，请检查网络后继续';
        phase = UpdateDownloadPhase.error;
      }
    } finally {
      if (_deleteOnStop) {
        await _discard(_partial);
        await _discard(_completed);
        received = 0;
      }
      _running = false;
      _notify();
    }
  }

  void _checkStopped(CancelToken token) {
    if (token.isCancelled) throw token.cancelError!;
    if (_disposed) throw StateError('disposed');
  }

  Future<void> _receive(
    GithubReleaseAsset next,
    String url,
    CancelToken token, {
    bool preserveResume = false,
  }) async {
    final partial = _partial!;
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset > next.size) {
      await _discard(partial);
      offset = 0;
    }
    received = offset;
    if (offset == next.size) return;
    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Accept-Encoding': 'identity',
          if (offset > 0) 'Range': 'bytes=$offset-',
        },
        validateStatus: (status) =>
            status == 200 || status == 206 || status == 416,
      ),
    );
    final body = response.data!;
    RandomAccessFile? output;
    var consumed = false;
    try {
      _checkStopped(token);
      if (response.statusCode == 416) {
        throw const FormatException('range unsatisfied');
      }
      if (response.statusCode == 206) {
        final range = RegExp(
          r'^bytes (\d+)-(\d+)/(\d+)$',
        ).firstMatch(response.headers.value('content-range') ?? '');
        if (range == null ||
            int.parse(range[1]!) != offset ||
            int.parse(range[2]!) != next.size - 1 ||
            int.parse(range[3]!) != next.size) {
          throw const FormatException('invalid content range');
        }
      } else {
        if (offset > 0 && preserveResume) throw _ResumeUnsupported();
        // Range was ignored. Truncate before writing, never append a full body.
        offset = 0;
      }
      final encoding = response.headers.value('content-encoding');
      if (encoding != null && encoding != 'identity') {
        throw const FormatException('encoded byte range');
      }
      final length = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (length != null && length != next.size - offset) {
        throw const FormatException('invalid content length');
      }
      output = await partial.open(
        mode: offset == 0 ? FileMode.write : FileMode.append,
      );
      received = offset;
      consumed = true;
      await for (final chunk in body.stream.timeout(
        const Duration(seconds: 30),
      )) {
        _checkStopped(token);
        if (received + chunk.length > next.size) {
          throw const FormatException('size mismatch');
        }
        await output.writeFrom(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (_lastProgress == null ||
            now.difference(_lastProgress!).inMilliseconds >= 100) {
          _lastProgress = now;
          _notify();
        }
      }
      if (received != next.size) {
        throw const HttpException('incomplete download');
      }
    } finally {
      await output?.close();
      if (!consumed) await body.stream.listen(null).cancel();
    }
  }

  Future<void> _discard(File? candidate) async {
    try {
      if (candidate != null && await candidate.exists()) {
        await candidate.delete();
      }
    } catch (_) {
      /* A locked partial remains disposable cache, never an installable result. */
    }
  }

  Future<bool> _validFile(File candidate, GithubReleaseAsset expected) async =>
      await candidate.exists() &&
      await candidate.length() == expected.size &&
      (await sha256.bind(candidate.openRead()).first).toString() ==
          expected.sha256Hex;

  void pause() {
    if (!busy) return;
    _cancel?.cancel();
    phase = UpdateDownloadPhase.paused;
    error = null;
    _notify();
  }

  Future<void> cancel() async {
    _deleteOnStop = true;
    _cancel?.cancel();
    phase = UpdateDownloadPhase.idle;
    received = 0;
    error = null;
    file = null;
    if (!busy) {
      _running = true;
      try {
        await _discard(_partial);
        await _discard(_completed);
      } finally {
        _running = false;
      }
    }
    _notify();
  }

  /// A false result with no error means Android needs installation permission.
  Future<bool> open({required String version}) async {
    final candidate = file;
    final expected = asset;
    if (candidate == null || expected == null) return false;
    try {
      if (!await _validFile(candidate, expected)) {
        phase = UpdateDownloadPhase.error;
        file = null;
        error = '安装包已失效，请重新下载';
        _notify();
        return false;
      }
      error = null;
      if (Platform.isAndroid) {
        return await updatePlatformChannel.invokeMethod<bool>('install', {
              'path': candidate.path,
              'version': version,
            }) ??
            false;
      }
      if (Platform.isWindows) {
        final result = await Process.run('explorer.exe', [
          '/select,${candidate.path}',
        ]);
        // Explorer may return 1 when forwarding to an existing instance.
        if (result.exitCode != 0 && result.exitCode != 1) {
          throw const FileSystemException();
        }
        return true;
      }
    } catch (_) {
      error = '无法打开安装包，请重试或前往发布页下载';
      _notify();
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    _dio.close(force: true);
    super.dispose();
  }
}
