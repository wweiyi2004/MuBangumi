import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/user_preference_store.dart';

class UserPreferencesState {
  const UserPreferencesState({
    this.preferences = const {},
    this.isLoading = false,
    this.error,
  });

  final Map<String, LocalUserPreference> preferences;
  final bool isLoading;
  final String? error;

  LocalUserPreference preferenceFor(String username) {
    final key = username.trim().toLowerCase();
    return preferences[key] ?? LocalUserPreference(username: key);
  }

  bool isBlocked(String username) => preferenceFor(username).blocked;

  UserPreferencesState copyWith({
    Map<String, LocalUserPreference>? preferences,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) => UserPreferencesState(
    preferences: preferences ?? this.preferences,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : error ?? this.error,
  );
}

class UserPreferencesController extends StateNotifier<UserPreferencesState> {
  UserPreferencesController(this._repository)
    : super(const UserPreferencesState(isLoading: true)) {
    unawaited(load());
  }

  final UserPreferenceRepository _repository;
  Future<void>? _loading;
  int _mutationGeneration = 0;
  bool _loaded = false;

  Future<void> load() {
    final active = _loading;
    if (active != null) return active;
    final future = _load();
    _loading = future;
    return future.whenComplete(() {
      if (identical(_loading, future)) _loading = null;
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = _mutationGeneration;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repository.loadAll();
      if (!mounted) return;
      if (generation != _mutationGeneration) {
        state = state.copyWith(isLoading: false);
        return;
      }
      _loaded = true;
      state = UserPreferencesState(
        preferences: {for (final item in items) item.key: item},
      );
    } catch (error) {
      if (!mounted || generation != _mutationGeneration) return;
      _loaded = false;
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> setNote(String username, String note) =>
      _update(username, (current) => current.copyWith(note: note.trim()));

  Future<void> setBlocked(String username, bool blocked) =>
      _update(username, (current) => current.copyWith(blocked: blocked));

  Future<void> _update(
    String username,
    LocalUserPreference Function(LocalUserPreference current) change,
  ) async {
    final key = username.trim().toLowerCase();
    if (key.isEmpty || !mounted) return;
    // A partial edit needs the complete saved record. Never replace fields
    // with defaults while the initial read is pending or has failed.
    if (!_loaded || state.isLoading) await load();
    if (!mounted) return;
    if (!_loaded) throw StateError('无法读取本地设置，请重试');
    final previous = state.preferenceFor(key);
    final next = change(previous);
    _mutationGeneration++;
    state = state.copyWith(
      preferences: {...state.preferences, key: next},
      isLoading: false,
      clearError: true,
    );
    try {
      await _repository.save(next);
    } catch (error) {
      if (!mounted) rethrow;
      // A failed older write must not roll back a newer edit to this user.
      final current = state.preferences[key];
      state = state.copyWith(
        preferences: identical(current, next)
            ? {...state.preferences, key: previous}
            : state.preferences,
        error: error.toString(),
      );
      rethrow;
    }
  }
}

final userPreferencesProvider =
    StateNotifierProvider<UserPreferencesController, UserPreferencesState>((
      ref,
    ) {
      return UserPreferencesController(UserPreferenceStore.shared);
    });
