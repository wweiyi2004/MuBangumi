import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Result of a Shorebird update check / download cycle.
enum AppUpdatePhase {
  /// Shorebird engine is not in this build (debug / non-shorebird release).
  unavailable,

  /// Already running the latest patch.
  upToDate,

  /// A newer patch can be downloaded.
  outdated,

  /// Patch is downloaded; app must restart to apply it.
  restartRequired,

  /// Check or download failed.
  error,
}

class AppUpdateSnapshot {
  const AppUpdateSnapshot({
    required this.phase,
    required this.appVersion,
    required this.buildNumber,
    this.currentPatch,
    this.nextPatch,
    this.releaseNotesMarkdown,
    this.message,
  });

  final AppUpdatePhase phase;
  final String appVersion;
  final String buildNumber;
  final int? currentPatch;
  final int? nextPatch;
  final String? releaseNotesMarkdown;
  final String? message;

  bool get isRestartReady => phase == AppUpdatePhase.restartRequired;

  String get versionLabel {
    final patch = currentPatch;
    if (patch == null) return '$appVersion+$buildNumber';
    return '$appVersion+$buildNumber · patch $patch';
  }
}

/// Builds the Markdown body shown in the update-ready dialog.
String buildUpdateReadyMarkdown({
  required String appVersion,
  required String buildNumber,
  int? nextPatch,
  String? releaseNotesMarkdown,
}) {
  final buffer = StringBuffer()
    ..writeln('## 热更新已就绪')
    ..writeln()
    ..writeln('当前版本：**$appVersion+$buildNumber**');
  if (nextPatch != null) {
    buffer
      ..writeln()
      ..writeln('即将应用：**Patch #$nextPatch**');
  }
  buffer
    ..writeln()
    ..writeln('重启应用后即可生效。本次为 **Shorebird 热更新**，无需重新安装安装包。');

  final notes = releaseNotesMarkdown?.trim();
  if (notes != null && notes.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('### 更新说明')
      ..writeln()
      ..writeln(notes);
  }
  return buffer.toString();
}

/// Abstraction over Shorebird + optional release notes so tests can fake it.
class AppUpdateService {
  AppUpdateService({
    ShorebirdUpdater? updater,
    Dio? dio,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _updater = updater ?? ShorebirdUpdater(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
               headers: const {
                 'Accept': 'application/vnd.github+json',
                 'User-Agent': 'MuBangumi-UpdateChecker',
               },
             ),
           ),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  static const githubLatestReleaseUrl =
      'https://api.github.com/repos/wweiyi2004/MuBangumi/releases/latest';

  final ShorebirdUpdater _updater;
  final Dio _dio;
  final Future<PackageInfo> Function() _packageInfoLoader;

  bool get isAvailable => _updater.isAvailable;

  Future<AppUpdateSnapshot> refresh({bool downloadIfOutdated = false}) async {
    final info = await _packageInfoLoader();
    final appVersion = info.version;
    final buildNumber = info.buildNumber;

    if (!_updater.isAvailable) {
      return AppUpdateSnapshot(
        phase: AppUpdatePhase.unavailable,
        appVersion: appVersion,
        buildNumber: buildNumber,
        message: '当前构建未启用 Shorebird（Debug 或非 shorebird release 包）',
      );
    }

    try {
      final current = await _safeReadPatch(() => _updater.readCurrentPatch());
      final status = await _updater.checkForUpdate();

      if (status == UpdateStatus.outdated && downloadIfOutdated) {
        await _updater.update();
        final next = await _safeReadPatch(() => _updater.readNextPatch());
        final notes = await _fetchReleaseNotesMarkdown();
        return AppUpdateSnapshot(
          phase: AppUpdatePhase.restartRequired,
          appVersion: appVersion,
          buildNumber: buildNumber,
          currentPatch: current?.number,
          nextPatch: next?.number,
          releaseNotesMarkdown: notes,
          message: '热更新已下载，请重启应用',
        );
      }

      switch (status) {
        case UpdateStatus.upToDate:
          return AppUpdateSnapshot(
            phase: AppUpdatePhase.upToDate,
            appVersion: appVersion,
            buildNumber: buildNumber,
            currentPatch: current?.number,
            message: '已是最新热更新',
          );
        case UpdateStatus.outdated:
          return AppUpdateSnapshot(
            phase: AppUpdatePhase.outdated,
            appVersion: appVersion,
            buildNumber: buildNumber,
            currentPatch: current?.number,
            message: '发现可用热更新',
          );
        case UpdateStatus.restartRequired:
          final next = await _safeReadPatch(() => _updater.readNextPatch());
          final notes = await _fetchReleaseNotesMarkdown();
          return AppUpdateSnapshot(
            phase: AppUpdatePhase.restartRequired,
            appVersion: appVersion,
            buildNumber: buildNumber,
            currentPatch: current?.number,
            nextPatch: next?.number,
            releaseNotesMarkdown: notes,
            message: '热更新已就绪，请重启应用',
          );
        case UpdateStatus.unavailable:
          return AppUpdateSnapshot(
            phase: AppUpdatePhase.unavailable,
            appVersion: appVersion,
            buildNumber: buildNumber,
            currentPatch: current?.number,
            message: '热更新服务暂不可用',
          );
      }
    } on UpdateException catch (error) {
      return AppUpdateSnapshot(
        phase: AppUpdatePhase.error,
        appVersion: appVersion,
        buildNumber: buildNumber,
        message: error.message,
      );
    } catch (error) {
      return AppUpdateSnapshot(
        phase: AppUpdatePhase.error,
        appVersion: appVersion,
        buildNumber: buildNumber,
        message: '检查热更新失败：$error',
      );
    }
  }

  Future<AppUpdateSnapshot> checkAndDownload() =>
      refresh(downloadIfOutdated: true);

  Future<Patch?> _safeReadPatch(Future<Patch?> Function() read) async {
    try {
      return await read();
    } on ReadPatchException {
      return null;
    }
  }

  /// Loads GitHub Release body (Markdown) for the latest published version.
  Future<String?> _fetchReleaseNotesMarkdown() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        githubLatestReleaseUrl,
      );
      final body = response.data?['body']?.toString().trim();
      if (body == null || body.isEmpty) return null;
      return body;
    } catch (_) {
      return null;
    }
  }
}
