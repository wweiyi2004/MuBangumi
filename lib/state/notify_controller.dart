import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../core/network/community_service.dart';
import '../models/community_models.dart';
import 'session_controller.dart';

typedef NoticeLoader = Future<CommunityPageResult<BangumiNotice>> Function();

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
  NotifyBadgeController({
    NoticeLoader? noticeLoader,
    bool Function()? isAuthenticated,
    DateTime Function()? now,
    bool initiallyForeground = true,
  }) : _noticeLoader =
           noticeLoader ??
           (() => CommunityService.shared.loadNotices(
             limit: 40,
             unreadOnly: true,
             refresh: true,
           )),
       _isAuthenticated =
           isAuthenticated ?? (() => CommunityService.shared.isAuthenticated),
       _now = now ?? DateTime.now,
       _foreground = initiallyForeground,
       super(const NotifyBadgeState());

  final NoticeLoader _noticeLoader;
  final bool Function() _isAuthenticated;
  final DateTime Function() _now;
  bool _foreground;
  DateTime? _lastRefresh;
  static const pollInterval = Duration(minutes: 3);
  Timer? _pollTimer;
  Future<void>? _inFlight;
  SessionPhase _phase = SessionPhase.booting;
  int _sessionGeneration = 0;
  int _refreshGeneration = 0;

  void updateSession(SessionPhase phase) {
    _sessionGeneration++;
    _inFlight = null;
    _lastRefresh = null;
    _phase = phase;
    if (phase == SessionPhase.signedIn && _foreground) {
      unawaited(refresh());
      _startPolling();
    } else {
      _stopPolling();
      state = const NotifyBadgeState();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Soft poll; P1 limit is modest and users expect a badge eventually.
    _pollTimer = Timer.periodic(pollInterval, (_) {
      unawaited(refresh());
    });
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _stopPolling();
    if (!foreground || _phase != SessionPhase.signedIn) return;
    final lastRefresh = _lastRefresh;
    if (lastRefresh == null || _now().difference(lastRefresh) >= pollInterval) {
      unawaited(refresh());
    }
    _startPolling();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refresh({bool force = false}) {
    if (!_foreground || !mounted) return Future.value();
    final existing = _inFlight;
    if (!force && existing != null) return existing;
    final future = _refresh();
    late final Future<void> tracked;
    tracked = future.whenComplete(() {
      if (identical(_inFlight, tracked)) _inFlight = null;
    });
    _inFlight = tracked;
    return tracked;
  }

  Future<void> _refresh() async {
    final sessionGeneration = _sessionGeneration;
    final refreshGeneration = ++_refreshGeneration;
    if (_phase != SessionPhase.signedIn) {
      state = const NotifyBadgeState();
      return;
    }
    if (!_isAuthenticated()) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await _noticeLoader();
      if (!mounted ||
          sessionGeneration != _sessionGeneration ||
          refreshGeneration != _refreshGeneration ||
          _phase != SessionPhase.signedIn ||
          !_isAuthenticated()) {
        return;
      }
      // API total is authoritative when present.
      final count = page.total > 0 ? page.total : page.data.length;
      _lastRefresh = _now();
      state = NotifyBadgeState(unreadCount: count);
    } catch (error) {
      if (!mounted ||
          sessionGeneration != _sessionGeneration ||
          refreshGeneration != _refreshGeneration ||
          _phase != SessionPhase.signedIn) {
        return;
      }
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
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final controller = NotifyBadgeController(
        initiallyForeground:
            lifecycle == null || lifecycle == AppLifecycleState.resumed,
      );
      ref.listen<SessionPhase>(
        sessionProvider.select((state) => state.phase),
        (_, phase) => controller.updateSession(phase),
        fireImmediately: true,
      );
      return controller;
    });
