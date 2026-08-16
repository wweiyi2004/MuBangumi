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

  Future<void> _loadVersionOnly() async {
    // Populate footer version; may also report Shorebird availability.
    final snapshot = await _service.refresh(downloadIfOutdated: false);
    if (!mounted) return;
    // Don't clobber a concurrent check that already finished.
    if (state.snapshot != null || state.busy) return;
    state = state.copyWith(snapshot: snapshot);
  }

  /// Silent check after login shell is ready. Downloads when outdated, then
  /// signals the UI to present the restart dialog at most once per patch.
  ///
  /// Call once per [UpdateCheckHost] mount (re-login remounts the host).
  Future<void> runStartupCheck({bool force = false}) async {
    if (_startupChecked && !force) return;
    _startupChecked = true;
    await _run(downloadIfOutdated: true, presentDialog: true);
  }

  /// Allow the next signed-in shell to run a startup Shorebird check again.
  void resetStartupCheckGate() {
    _startupChecked = false;
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
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final snapshot = await _service.refresh(
        downloadIfOutdated: downloadIfOutdated,
      );
      final patchKey = snapshot.nextPatch ?? snapshot.currentPatch ?? -1;
      final shouldPresent =
          presentDialog &&
          snapshot.isRestartReady &&
          !_promptedPatches.contains(patchKey);

      if (shouldPresent) {
        _promptedPatches.add(patchKey);
      }

      final github = snapshot.isRestartReady
          ? null
          : await _loadGithubOffer(
              currentVersion: snapshot.appVersion,
              ignoreSkip: ignoreGithubSkip,
            );
      final shouldPresentGithub =
          presentDialog &&
          github != null &&
          !_promptedGithubTags.contains(github.tagName);
      if (shouldPresentGithub) {
        _promptedGithubTags.add(github.tagName);
      }

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
        appVersion: state.snapshot?.appVersion ?? '?',
        buildNumber: state.snapshot?.buildNumber ?? '?',
        message: '检查更新失败：$error',
      );
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
    final skipped = ignoreSkip ? null : await _skipStore.readSkippedTag();
    if (!shouldOfferGithubRelease(
      currentVersion: currentVersion,
      release: release,
      skippedTag: skipped,
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
    state = state.copyWith(
      clearGithub: true,
      shouldPresentGithubDialog: false,
    );
  }

  /// Fully exits so the next cold start loads the downloaded Shorebird patch.
  void restartApp() {
    // Process exit is required; Flutter hot-restart would not reload the engine
    // patch cache on device/desktop release builds.
    if (kIsWeb) return;
    exit(0);
  }
}
