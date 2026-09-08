import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/browsing_store.dart';
import '../models/recommendation_feedback.dart';

class RecommendationFeedbackFailure {
  const RecommendationFeedbackFailure({
    required this.item,
    required this.hiding,
  });
  final HiddenRecommendation item;
  final bool hiding;
  String get message =>
      hiding ? '未能保存对《${item.title}》的反馈，已恢复原显示' : '未能恢复《${item.title}》，请重试';
}

class RecommendationFeedbackState {
  const RecommendationFeedbackState({
    this.hidden = const {},
    this.pending = const {},
    this.loading = true,
    this.ready = false,
    this.failure,
    this.loadError,
  });
  final Map<int, HiddenRecommendation> hidden;
  final Set<int> pending;
  final bool loading, ready;
  final RecommendationFeedbackFailure? failure;
  final String? loadError;
  String? get error => loadError ?? failure?.message;
}

final recommendationFeedbackProvider = StateNotifierProvider.autoDispose
    .family<RecommendationFeedbackController, RecommendationFeedbackState, int>(
      (ref, ownerId) => RecommendationFeedbackController(
        ref.watch(recommendationFeedbackRepositoryProvider),
        ownerId,
      ),
    );

class RecommendationFeedbackController
    extends StateNotifier<RecommendationFeedbackState> {
  RecommendationFeedbackController(this.repository, this.ownerId)
    : super(const RecommendationFeedbackState()) {
    unawaited(load());
  }
  final RecommendationFeedbackRepository repository;
  final int ownerId;
  int _generation = 0;
  Future<void> _operations = Future.value();

  Future<void> load() async {
    if (!mounted || state.pending.isNotEmpty) return;
    final generation = ++_generation;
    state = RecommendationFeedbackState(hidden: state.hidden);
    try {
      await _operations;
      final items = await repository.readHiddenRecommendations(ownerId);
      if (mounted && generation == _generation) {
        state = RecommendationFeedbackState(
          hidden: Map.unmodifiable({
            for (final item in items) item.subjectId: item,
          }),
          loading: false,
          ready: true,
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        state = RecommendationFeedbackState(
          hidden: state.hidden,
          loading: false,
          loadError: '不感兴趣记录读取失败，请重试',
        );
      }
    }
  }

  Future<bool> hide(HiddenRecommendation item) => _change(item, hiding: true);
  Future<bool> restore(int subjectId) {
    if (!mounted || !state.ready || state.loading) return Future.value(false);
    final item = state.hidden[subjectId];
    return item == null ? Future.value(true) : _change(item, hiding: false);
  }

  Future<bool> _change(HiddenRecommendation item, {required bool hiding}) {
    if (!mounted ||
        !state.ready ||
        state.loading ||
        state.pending.contains(item.subjectId)) {
      return Future.value(false);
    }
    final previous = state.hidden[item.subjectId];
    if ((previous != null) == hiding) return Future.value(true);
    _generation++;
    final hidden = {...state.hidden};
    if (hiding) {
      hidden[item.subjectId] = item;
    } else {
      hidden.remove(item.subjectId);
    }
    state = RecommendationFeedbackState(
      hidden: Map.unmodifiable(hidden),
      pending: {...state.pending, item.subjectId},
      loading: false,
      ready: true,
    );
    final operation = _operations.then((_) async {
      try {
        if (hiding) {
          await repository.hideRecommendation(ownerId, item);
        } else {
          await repository.restoreRecommendation(ownerId, item.subjectId);
        }
        if (mounted) {
          state = RecommendationFeedbackState(
            hidden: state.hidden,
            pending: {...state.pending}..remove(item.subjectId),
            loading: false,
            ready: true,
            failure: state.failure,
          );
        }
        return true;
      } catch (_) {
        if (mounted) {
          final restored = {...state.hidden};
          if (previous == null) {
            restored.remove(item.subjectId);
          } else {
            restored[item.subjectId] = previous;
          }
          state = RecommendationFeedbackState(
            hidden: Map.unmodifiable(restored),
            pending: {...state.pending}..remove(item.subjectId),
            loading: false,
            ready: true,
            failure: RecommendationFeedbackFailure(item: item, hiding: hiding),
          );
        }
        return false;
      }
    });
    _operations = operation.then<void>((_) {});
    return operation;
  }

  Future<void> retry() async {
    if (!mounted) return;
    if (!state.ready) {
      await load();
      return;
    }
    final failure = state.failure;
    if (failure != null) await _change(failure.item, hiding: failure.hiding);
  }
}
