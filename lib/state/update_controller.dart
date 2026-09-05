import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/update/app_update_service.dart';
import '../core/update/github_release.dart';
import '../core/update/github_release_store.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService();
});

final updateControllerProvider =
    StateNotifierProvider<UpdateController, UpdateUiState>((ref) {
      return UpdateController(
        ref.watch(appUpdateServiceProvider),
        GithubReleaseSkipStore(),
      );
    });

class UpdateUiState {
  const UpdateUiState({
    this.busy = false,
    this.snapshot,
    this.githubRelease,
    this.lastError,
    this.shouldPresentRestartDialog = false,
    this.shouldPresentGithubDialog = false,
  });

  final bool busy;
  final AppUpdateSnapshot? snapshot;
  final GithubRelease? githubRelease;
  final String? lastError;

  /// Set when a restart-ready update should be shown once by the host UI.
  final bool shouldPresentRestartDialog;

  /// Set when a newer GitHub Release should be shown once by the host UI.
  final bool shouldPresentGithubDialog;

  UpdateUiState copyWith({
    bool? busy,
    AppUpdateSnapshot? snapshot,
    GithubRelease? githubRelease,
    bool clearGithub = false,
    String? lastError,
    bool clearError = false,
    bool? shouldPresentRestartDialog,
    bool? shouldPresentGithubDialog,
  }) => UpdateUiState(
    busy: busy ?? this.busy,
    snapshot: snapshot ?? this.snapshot,
    githubRelease: clearGithub ? null : githubRelease ?? this.githubRelease,
    lastError: clearError ? null : lastError ?? this.lastError,
    shouldPresentRestartDialog:
        shouldPresentRestartDialog ?? this.shouldPresentRestartDialog,
    shouldPresentGithubDialog:
        shouldPresentGithubDialog ?? this.shouldPresentGithubDialog,
  );
}

class UpdateController extends StateNotifier<UpdateUiState> {
  UpdateController(this._service, this._skipStore)
    : super(const UpdateUiState()) {
    unawaited(_loadVersionOnly());
  }

  final AppUpdateService _service;
  final GithubReleaseSkipStore _skipStore;

  /// Patch numbers already shown in this process (session-once dialogs).
  final Set<int> _promptedPatches = <int>{};
  final Set<String> _promptedGithubTags = <String>{};
  bool _startupChecked = false;
  DateTime? _lastCheckAt;
  Future<AppUpdateSnapshot>? _inFlight;
  bool _manualRequested = false;

  Future<void> _loadVersionOnly() async {
    // Populate footer version; may also report Shorebird availability.
    AppUpdateSnapshot snapshot;
    try {
      snapshot = await _service.readInstalledVersion();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    // Don't clobber a concurrent check that already finished.
    if (state.snapshot != null || state.busy) return;
    state = state.copyWith(snapshot: snapshot);
  }

  /// Silent check after the first frame or a throttled foreground resume. Downloads when outdated, then
  /// signals the UI to present the restart dialog at most once per patch.
  ///
  /// [UpdateCheckHost] remains mounted across login changes.
  Future<void> runStartupCheck({bool force = false}) async {
    if (_startupChecked &&
        !force &&
        _lastCheckAt != null &&
        DateTime.now().difference(_lastCheckAt!) <
            const Duration(minutes: 30)) {
      return;
    }
    _startupChecked = true;
    await _run(downloadIfOutdated: true, presentDialog: true);
  }

  /// Manual check from 我的. Caller owns any UI (dialog / snackbar).
  Future<AppUpdateSnapshot> checkNow({bool downloadIfOutdated = true}) async {
    // presentDialog: false — avoid double dialog with UpdateCheckHost listener.
    return _run(
      downloadIfOutdated: downloadIfOutdated,
      presentDialog: false,
      ignoreGithubSkip: true,
    );
  }

  Future<AppUpdateSnapshot> _run({
    required bool downloadIfOutdated,
    required bool presentDialog,
    bool ignoreGithubSkip = false,
  }) {
    if (ignoreGithubSkip) _manualRequested = true;
    final pending = _inFlight;
    if (pending != null) return pending;
    _manualRequested = ignoreGithubSkip;
    final operation = _performRun(
      downloadIfOutdated: downloadIfOutdated,
      presentDialog: presentDialog,
    );
    _inFlight = operation;
    return operation.whenComplete(() {
      _inFlight = null;
      _manualRequested = false;
    });
  }

  Future<AppUpdateSnapshot> _performRun({
    required bool downloadIfOutdated,
    required bool presentDialog,
  }) async {
    _lastCheckAt = DateTime.now();
    state = state.copyWith(
      busy: true,
      clearError: true,
      shouldPresentRestartDialog: false,
      shouldPresentGithubDialog: false,
    );
    try {
      final snapshot = await _service.refresh(
        downloadIfOutdated: downloadIfOutdated,
      );
      if (!mounted) return snapshot;
      final patchKey = snapshot.nextPatch ?? snapshot.currentPatch ?? -1;
      final shouldPresent =
          presentDialog &&
          !_manualRequested &&
          snapshot.isRestartReady &&
          !_promptedPatches.contains(patchKey);

      if (shouldPresent) {
        _promptedPatches.add(patchKey);
      }

      final github = snapshot.isRestartReady
          ? null
          : await _loadGithubOffer(
              currentVersion: snapshot.appVersion,
              ignoreSkip: _manualRequested,
            );
      final shouldPresentGithub =
          presentDialog &&
          !_manualRequested &&
          github != null &&
          !_promptedGithubTags.contains(github.tagName);
      if (shouldPresentGithub) {
        _promptedGithubTags.add(github.tagName);
      }

      if (!mounted) return snapshot;
      state = state.copyWith(
        busy: false,
        snapshot: snapshot,
        githubRelease: github,
        clearGithub: github == null,
        shouldPresentRestartDialog: shouldPresent,
        shouldPresentGithubDialog: shouldPresentGithub,
        lastError: snapshot.phase == AppUpdatePhase.error
            ? snapshot.message
            : null,
      );
      return snapshot;
    } catch (error) {
      final fallback = AppUpdateSnapshot(
        phase: AppUpdatePhase.error,
        appVersion: mounted ? state.snapshot?.appVersion ?? '?' : '?',
        buildNumber: mounted ? state.snapshot?.buildNumber ?? '?' : '?',
        message: '检查更新失败：$error',
      );
      if (!mounted) return fallback;
      state = state.copyWith(
        busy: false,
        snapshot: fallback,
        clearGithub: true,
        lastError: fallback.message,
        shouldPresentRestartDialog: false,
        shouldPresentGithubDialog: false,
      );
      return fallback;
    }
  }

  Future<GithubRelease?> _loadGithubOffer({
    required String currentVersion,
    required bool ignoreSkip,
  }) async {
    final release = await _service.fetchLatestGithubRelease();
    if (release == null) return null;
    String? skipped;
    if (!ignoreSkip) {
      try {
        skipped = await _skipStore.readSkippedTag();
      } catch (_) {}
    }
    if (!shouldOfferGithubRelease(
      currentVersion: currentVersion,
      release: release,
      skippedTag: _manualRequested ? null : skipped,
    )) {
      return null;
    }
    return release;
  }

  void acknowledgeRestartDialog() {
    if (!state.shouldPresentRestartDialog) return;
    state = state.copyWith(shouldPresentRestartDialog: false);
  }

  void acknowledgeGithubDialog() {
    if (!state.shouldPresentGithubDialog) return;
    state = state.copyWith(shouldPresentGithubDialog: false);
  }

  Future<void> skipGithubRelease(GithubRelease release) async {
    await _skipStore.skipTag(release.tagName);
    if (!mounted) return;
    state = state.copyWith(clearGithub: true, shouldPresentGithubDialog: false);
  }

  /// Fully exits so the next cold start loads the downloaded Shorebird patch.
  void restartApp() {
    // Process exit is required; Flutter hot-restart would not reload the engine
    // patch cache on device/desktop release builds.
    if (kIsWeb) return;
    exit(0);
  }
}
