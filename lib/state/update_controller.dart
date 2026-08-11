import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/update/app_update_service.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService();
});

final updateControllerProvider =
    StateNotifierProvider<UpdateController, UpdateUiState>((ref) {
      return UpdateController(ref.watch(appUpdateServiceProvider));
    });

class UpdateUiState {
  const UpdateUiState({
    this.busy = false,
    this.snapshot,
    this.lastError,
    this.shouldPresentRestartDialog = false,
  });

  final bool busy;
  final AppUpdateSnapshot? snapshot;
  final String? lastError;

  /// Set when a restart-ready update should be shown once by the host UI.
  final bool shouldPresentRestartDialog;

  UpdateUiState copyWith({
    bool? busy,
    AppUpdateSnapshot? snapshot,
    String? lastError,
    bool clearError = false,
    bool? shouldPresentRestartDialog,
  }) => UpdateUiState(
    busy: busy ?? this.busy,
    snapshot: snapshot ?? this.snapshot,
    lastError: clearError ? null : lastError ?? this.lastError,
    shouldPresentRestartDialog:
        shouldPresentRestartDialog ?? this.shouldPresentRestartDialog,
  );
}

class UpdateController extends StateNotifier<UpdateUiState> {
  UpdateController(this._service) : super(const UpdateUiState()) {
    unawaited(_loadVersionOnly());
  }

  final AppUpdateService _service;

  /// Patch numbers already shown in this process (session-once dialogs).
  final Set<int> _promptedPatches = <int>{};
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
    return _run(downloadIfOutdated: downloadIfOutdated, presentDialog: false);
  }

  Future<AppUpdateSnapshot> _run({
    required bool downloadIfOutdated,
    required bool presentDialog,
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

      state = state.copyWith(
        busy: false,
        snapshot: snapshot,
        shouldPresentRestartDialog: shouldPresent,
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
        message: '检查热更新失败：$error',
      );
      state = state.copyWith(
        busy: false,
        snapshot: fallback,
        lastError: fallback.message,
        shouldPresentRestartDialog: false,
      );
      return fallback;
    }
  }

  void acknowledgeRestartDialog() {
    if (!state.shouldPresentRestartDialog) return;
    state = state.copyWith(shouldPresentRestartDialog: false);
  }

  /// Fully exits so the next cold start loads the downloaded Shorebird patch.
  void restartApp() {
    // Process exit is required; Flutter hot-restart would not reload the engine
    // patch cache on device/desktop release builds.
    if (kIsWeb) return;
    exit(0);
  }
}
