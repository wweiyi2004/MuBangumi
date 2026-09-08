import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/browsing_store.dart';
import '../models/bangumi_models.dart';

class HomePinsState {
  const HomePinsState({
    this.ids = const [],
    this.loading = true,
    this.saving = false,
    this.error,
  });
  final List<int> ids;
  final bool loading;
  final bool saving;
  final String? error;
}

final homePinsProvider = StateNotifierProvider.autoDispose
    .family<HomePinsController, HomePinsState, int>(
      (ref, ownerId) =>
          HomePinsController(ref.watch(homePinsRepositoryProvider), ownerId),
    );

class HomePinsController extends StateNotifier<HomePinsState> {
  HomePinsController(this.repository, this.ownerId)
    : super(const HomePinsState()) {
    unawaited(load());
  }
  final HomePinsRepository repository;
  final int ownerId;
  bool _loaded = false;
  int _generation = 0;
  bool get canEdit => mounted && _loaded && !state.loading && !state.saving;

  Future<void> load() async {
    if (!mounted || state.saving) return;
    final generation = ++_generation;
    _loaded = false;
    state = HomePinsState(ids: state.ids);
    try {
      final ids = await repository.readHomePins(ownerId);
      if (mounted && generation == _generation) {
        _loaded = true;
        state = HomePinsState(
          ids: List.unmodifiable(ids.toSet()),
          loading: false,
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        state = HomePinsState(
          ids: state.ids,
          loading: false,
          error: '首页置顶读取失败，请重试',
        );
      }
    }
  }

  Future<void> setPinned(int id, bool pinned) {
    if (!mounted || id <= 0 || state.ids.contains(id) == pinned) {
      return Future.value();
    }
    return _save(
      pinned
          ? [...state.ids, id]
          : state.ids.where((item) => item != id).toList(),
    );
  }

  Future<void> move(int id, int targetId) {
    if (!mounted) return Future.value();
    final ids = [...state.ids];
    final from = ids.indexOf(id), target = ids.indexOf(targetId);
    if (from < 0 || target < 0 || from == target) return Future.value();
    ids.removeAt(from);
    ids.insert(target, id);
    return _save(ids);
  }

  Future<void> _save(List<int> ids) async {
    if (!_loaded || state.loading || state.saving) return;
    final previous = state.ids;
    state = HomePinsState(ids: previous, loading: false, saving: true);
    try {
      await repository.saveHomePins(ownerId, ids);
      if (mounted) {
        state = HomePinsState(ids: List.unmodifiable(ids), loading: false);
      }
    } catch (_) {
      if (mounted) {
        state = HomePinsState(
          ids: previous,
          loading: false,
          error: '置顶未能保存，已保留原顺序，请重试操作',
        );
      }
    }
  }
}

List<UserCollection> orderHomeCollections(
  List<UserCollection> collections,
  List<int> pins,
) {
  final watching = <int, UserCollection>{};
  for (final item in collections) {
    if (item.type == CollectionType.doing) {
      watching.putIfAbsent(item.subjectId, () => item);
    }
  }
  final result = <UserCollection>[];
  for (final id in pins) {
    final item = watching.remove(id);
    if (item != null) result.add(item);
  }
  return [...result, ...watching.values];
}
