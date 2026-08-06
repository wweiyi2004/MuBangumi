import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/community_service.dart';
import 'session_controller.dart';

class NotifyBadgeState {
  const NotifyBadgeState({
    this.unreadCount = 0,
    this.isLoading = false,
    this.lastError,
  });

  final int unreadCount;
  final bool isLoading;
  final String? lastError;

  NotifyBadgeState copyWith({
    int? unreadCount,
    bool? isLoading,
    String? lastError,
    bool clearError = false,
  }) => NotifyBadgeState(
    unreadCount: unreadCount ?? this.unreadCount,
    isLoading: isLoading ?? this.isLoading,
    lastError: clearError ? null : lastError ?? this.lastError,
  );
}

class NotifyBadgeController extends StateNotifier<NotifyBadgeState> {
  NotifyBadgeController(this._ref) : super(const NotifyBadgeState()) {
    _ref.listen<SessionPhase>(
      sessionProvider.select((s) => s.phase),
      (previous, next) {
        if (next == SessionPhase.signedIn) {
          unawaited(refresh());
          _startPolling();
        } else {
          _stopPolling();
          state = const NotifyBadgeState();
        }
      },
      fireImmediately: true,
    );
  }

  final Ref _ref;
  Timer? _pollTimer;
  Future<void>? _inFlight;

  void _startPolling() {
    _pollTimer?.cancel();
    // Soft poll; P1 limit is modest and users expect a badge eventually.
    _pollTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      unawaited(refresh());
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refresh({bool force = false}) {
    final existing = _inFlight;
    if (!force && existing != null) return existing;
    final future = _refresh();
    _inFlight = future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return _inFlight!;
  }

  Future<void> _refresh() async {
    final phase = _ref.read(sessionProvider).phase;
    if (phase != SessionPhase.signedIn) {
      state = const NotifyBadgeState();
      return;
    }
    if (!CommunityService.shared.isAuthenticated) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await CommunityService.shared.loadNotices(
        limit: 40,
        unreadOnly: true,
        refresh: true,
      );
      // API total is authoritative when present.
      final count = page.total > 0 ? page.total : page.data.length;
      state = NotifyBadgeState(unreadCount: count);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        lastError: error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void setUnreadCount(int count) {
    state = state.copyWith(
      unreadCount: count < 0 ? 0 : count,
      isLoading: false,
      clearError: true,
    );
  }

  void markOneReadLocally() {
    final next = state.unreadCount - 1;
    state = state.copyWith(unreadCount: next < 0 ? 0 : next);
  }

  void clearLocally() {
    state = state.copyWith(unreadCount: 0, isLoading: false, clearError: true);
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

final notifyBadgeProvider =
    StateNotifierProvider<NotifyBadgeController, NotifyBadgeState>((ref) {
      return NotifyBadgeController(ref);
    });
