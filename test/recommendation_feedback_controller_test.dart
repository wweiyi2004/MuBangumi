import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/recommendation_feedback.dart';
import 'package:mubangumi/state/recommendation_feedback_controller.dart';

import 'support/memory_recommendation_feedback.dart';

void main() {
  test(
    'feedback hides immediately, persists, and restores independently for each account',
    () async {
      final repo = MemoryRecommendationFeedback();
      final controller = RecommendationFeedbackController(repo, 1);
      addTearDown(controller.dispose);
      await pumpEventQueue();
      final gate = Completer<void>();
      repo.pendingWrite = gate.future;
      final hide = controller.hide(_item(7));
      expect(controller.state.hidden.keys, [7]);
      expect(controller.state.pending, {7});
      gate.complete();
      expect(await hide, isTrue);
      expect(controller.state.pending, isEmpty);
      final other = RecommendationFeedbackController(repo, 2);
      addTearDown(other.dispose);
      await pumpEventQueue();
      expect(other.state.hidden, isEmpty);
      await other.hide(_item(7));
      expect(await controller.restore(7), isTrue);
      expect(repo.records[1], isEmpty);
      expect(repo.records[2]!.keys, [7]);
    },
  );

  test(
    'a failed hide rolls back only its own subject while another write succeeds',
    () async {
      final repo = MemoryRecommendationFeedback()..failedSubjects.add(7);
      final controller = RecommendationFeedbackController(repo, 1);
      addTearDown(controller.dispose);
      await pumpEventQueue();
      expect(
        await Future.wait([
          controller.hide(_item(7)),
          controller.hide(_item(8)),
        ]),
        [false, true],
      );
      expect(controller.state.hidden.keys, [8]);
      expect(controller.state.error, contains('作品7'));
      repo.failedSubjects.clear();
      await controller.retry();
      expect(controller.state.hidden.keys.toSet(), {7, 8});
      expect(repo.records[1]!.keys.toSet(), {7, 8});
    },
  );

  test(
    'failed restoration keeps the hidden record and retry does not hide another subject',
    () async {
      final repo = MemoryRecommendationFeedback()..records[1] = {7: _item(7)};
      final controller = RecommendationFeedbackController(repo, 1);
      addTearDown(controller.dispose);
      await pumpEventQueue();
      repo.failedSubjects.add(7);
      expect(await controller.restore(7), isFalse);
      expect(controller.state.hidden.keys, [7]);
      expect(controller.state.error, contains('未能恢复'));
      repo.failedSubjects.clear();
      await controller.retry();
      expect(controller.state.hidden, isEmpty);
    },
  );

  test(
    'loading errors block blind feedback changes until a successful retry',
    () async {
      final repo = MemoryRecommendationFeedback()
        ..records[1] = {7: _item(7)}
        ..failRead = true;
      final controller = RecommendationFeedbackController(repo, 1);
      addTearDown(controller.dispose);
      await pumpEventQueue();
      expect(controller.state.ready, isFalse);
      expect(await controller.hide(_item(8)), isFalse);
      expect(await controller.restore(7), isFalse);
      expect(repo.writes, 0);
      repo.failRead = false;
      await controller.retry();
      expect(controller.state.hidden.keys, [7]);
    },
  );

  test(
    'a pending old-account write finishes only for that owner after disposal',
    () async {
      final repo = MemoryRecommendationFeedback();
      final old = RecommendationFeedbackController(repo, 1);
      await pumpEventQueue();
      final gate = Completer<void>();
      repo.pendingWrite = gate.future;
      final saving = old.hide(_item(7));
      await pumpEventQueue();
      expect(await old.hide(_item(7)), isFalse);
      expect(repo.writes, 1);
      old.dispose();
      final current = RecommendationFeedbackController(repo, 2);
      addTearDown(current.dispose);
      gate.complete();
      expect(await saving, isTrue);
      await pumpEventQueue();
      expect(current.state.hidden, isEmpty);
      expect(repo.records[1]!.keys, [7]);
    },
  );

  test('a late old load cannot overwrite a newer reload', () async {
    final repo = MemoryRecommendationFeedback();
    final first = Completer<List<HiddenRecommendation>>(),
        second = Completer<List<HiddenRecommendation>>();
    repo.pendingRead = first.future;
    final controller = RecommendationFeedbackController(repo, 1);
    addTearDown(controller.dispose);
    await pumpEventQueue();
    repo.pendingRead = second.future;
    final loading = controller.load();
    second.complete([_item(8)]);
    await loading;
    first.complete([_item(7)]);
    await pumpEventQueue();
    expect(controller.state.hidden.keys, [8]);
  });
}

HiddenRecommendation _item(int id) => HiddenRecommendation(
  subjectId: id,
  title: '作品$id',
  type: SubjectType.anime,
  hiddenAt: DateTime(2026, 9, 8),
);
