import 'dart:math';

import 'bangumi_models.dart';
import 'schedule_models.dart';

enum LibraryBatchKind { collection, schedule }

enum LibraryBatchStatus { notStarted, processing, saved, skipped, failed }

class LibraryBatchAccount {
  const LibraryBatchAccount({
    required this.userId,
    required this.username,
    required this.generation,
  });
  final int userId;
  final String username;
  final int generation;
}

class LibraryBatchItem {
  const LibraryBatchItem({required this.subject, required this.revision});
  final Subject subject;
  final int revision;
  int get id => subject.id;
}

class LibraryBatchPlan {
  LibraryBatchPlan({
    required this.account,
    required this.kind,
    required List<LibraryBatchItem> items,
    this.collectionType = CollectionType.done,
    this.completeEpisodes = false,
    this.season,
    this.weekday,
    String? operationId,
  }) : items = List.unmodifiable(
         {for (final item in items) item.id: item}.values,
       ),
       operationId =
           operationId ??
           '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
  final String operationId;
  final LibraryBatchAccount account;
  final LibraryBatchKind kind;
  final List<LibraryBatchItem> items;
  final CollectionType collectionType;
  final bool completeEpisodes;
  final SeasonKey? season;
  final int? weekday;
}

class LibraryBatchOutcome {
  const LibraryBatchOutcome(this.status, {this.message});
  final LibraryBatchStatus status;
  final String? message;
}

class ScheduleBatchAddResult {
  const ScheduleBatchAddResult({
    this.added = const {},
    this.existing = const {},
    this.error,
    this.stopped = false,
    this.warning,
  });
  final Set<int> added, existing;
  final String? error, warning;
  final bool stopped;
}

class LibraryBatchGroupResult {
  const LibraryBatchGroupResult(this.outcomes, {this.warning});
  final Map<int, LibraryBatchOutcome> outcomes;
  final String? warning;
}

String batchCollectionLabel(CollectionType type) => switch (type) {
  CollectionType.wish => '计划中',
  CollectionType.doing => '进行中',
  CollectionType.done => '已完成',
  CollectionType.onHold => '搁置',
  CollectionType.dropped => '抛弃',
};
