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

enum UpdateDownloadPhase { idle, downloading, verifying, ready, error }

final updateDownloadProvider = Provider<UpdateDownload>((ref) {
  final download = UpdateDownload();
  ref.onDispose(download.dispose);
  return download;
});

class UpdateDownload extends ChangeNotifier {
  UpdateDownload({Dio? dio, Future<Directory> Function()? directory})
    : _dio =
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
            p.join((await getTemporaryDirectory()).path, 'mubangumi-updates'),
          ));

  final Dio _dio;
  final Future<Directory> Function() _directory;
  UpdateDownloadPhase phase = UpdateDownloadPhase.idle;
  GithubReleaseAsset? asset;
  GithubRelease? release;
  File? file;
  String? error;
  int received = 0;
  CancelToken? _cancel;
  int _generation = 0;
  bool _disposed = false;
  DateTime? _lastProgress;
  bool get busy =>
      phase == UpdateDownloadPhase.downloading ||
      phase == UpdateDownloadPhase.verifying;
  double? get progress =>
      asset == null ? null : (received / asset!.size).clamp(0, 1);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start(GithubReleaseAsset next) async {
    if (busy) return;
    if (!next.trustedDownload) {
      error = '安装包缺少有效校验信息，请前往发布页下载';
      phase = UpdateDownloadPhase.error;
      _notify();
      return;
    }
    final generation = ++_generation;
    final token = _cancel = CancelToken();
    asset = next;
    file = null;
    error = null;
    received = 0;
    phase = UpdateDownloadPhase.downloading;
    _notify();
    File? partial;
    File? completed;
    try {
      final directory = await _directory();
      await directory.create(recursive: true);
      // Unique names keep late cancellation/cleanup from touching a newer task.
      final stem = '${next.sha256Hex}-${DateTime.now().microsecondsSinceEpoch}';
      partial = File(p.join(directory.path, '$stem.partial'));
      completed = File(
        p.join(
          directory.path,
          '${p.basenameWithoutExtension(next.name)}-${DateTime.now().microsecondsSinceEpoch}${p.extension(next.name)}',
        ),
      );
      await _dio.download(
        next.url,
        partial.path,
        cancelToken: token,
        onReceiveProgress: (count, total) {
          if (count > next.size) {
            token.cancel('size mismatch');
            return;
          }
          if (generation != _generation || _disposed) return;
          received = count;
          final now = DateTime.now();
          if (count == next.size ||
              _lastProgress == null ||
              now.difference(_lastProgress!).inMilliseconds >= 100) {
            _lastProgress = now;
            _notify();
          }
        },
      );
      if (generation != _generation || _disposed) return;
      phase = UpdateDownloadPhase.verifying;
      _notify();
      if (!await _validFile(partial, next)) {
        throw const FormatException('digest');
      }
      if (generation != _generation || _disposed) return;
      await partial.rename(completed.path);
      if (generation != _generation || _disposed) return;
      file = completed;
      phase = UpdateDownloadPhase.ready;
    } catch (e) {
      if (generation != _generation || _disposed) return;
      error = e is FormatException ? '安装包校验失败，请重新下载' : '下载未完成，请检查网络后重试';
      phase = UpdateDownloadPhase.error;
    } finally {
      await _discard(partial);
      if (completed?.path != file?.path) await _discard(completed);
      _notify();
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

  void cancel() {
    ++_generation;
    _cancel?.cancel();
    phase = UpdateDownloadPhase.idle;
    received = 0;
    error = null;
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
    cancel();
    _dio.close(force: true);
    super.dispose();
  }
}
