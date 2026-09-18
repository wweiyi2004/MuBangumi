import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/bangumi_api.dart';
import '../../../core/network/bangumi_support.dart';
import '../../../core/network/moegirl_service.dart';
import '../../../core/network/netaba_api.dart';
import '../../../models/bangumi_models.dart';
import '../../../models/community_models.dart';
import '../../../models/netaba_models.dart';
import 'subject_detail_resource.dart';

class SubjectMetadata {
  const SubjectMetadata({
    this.characters = const [],
    this.persons = const [],
    this.related = const [],
    this.warning,
  });
  final List<SubjectCharacter> characters;
  final List<SubjectPerson> persons;
  final List<RelatedSubject> related;
  final String? warning;
}

/// Independent public sections; a failed or slow section never blocks another.
class SubjectSupplementController extends ChangeNotifier {
  SubjectSupplementController({
    required Subject subject,
    required BangumiApi Function() api,
    required Future<NetabaSubjectHistory> Function(int) loadHistory,
    required Future<List<CommunityTopic>> Function(int) loadTopics,
    required Future<MoegirlEntry?> Function(
      Subject, {
      required bool forceRefresh,
    })
    findMoegirl,
  }) {
    details = SubjectDetailResource(
      initial: subject,
      request: () => api().getSubject(subject.id),
      errorMessage: (_) => '详情加载失败',
    );
    metadata = SubjectDetailResource(
      initial: const SubjectMetadata(),
      request: () => _loadMetadata(api(), subject.id),
      errorMessage: (_) => '角色 / 制作人员 / 关联条目加载失败',
    );
    topics = SubjectDetailResource<List<CommunityTopic>>(
      initial: const [],
      request: () => loadTopics(subject.id),
      errorMessage: (_) => '讨论加载失败',
    );
    history = SubjectDetailResource<NetabaSubjectHistory?>(
      initial: null,
      request: () => loadHistory(subject.id),
      errorMessage: _historyErrorMessage,
    );
    moegirl = SubjectDetailResource<MoegirlEntry?>(
      initial: null,
      request: () => findMoegirl(
        subject.merge(details.value),
        forceRefresh: moegirl.attempts > 1,
      ),
      errorMessage: (error) =>
          error is MoegirlException ? error.message : '获取萌娘百科资料失败，请稍后重试',
    );
    for (final section in _sections) {
      section.addListener(notifyListeners);
    }
  }

  late final SubjectDetailResource<Subject> details;
  late final SubjectDetailResource<SubjectMetadata> metadata;
  late final SubjectDetailResource<List<CommunityTopic>> topics;
  late final SubjectDetailResource<NetabaSubjectHistory?> history;
  late final SubjectDetailResource<MoegirlEntry?> moegirl;
  List<ChangeNotifier> get _sections => [
    details,
    metadata,
    topics,
    history,
    moegirl,
  ];

  Future<void> load() async {
    unawaited(metadata.load());
    unawaited(topics.load());
    unawaited(history.load());
    await details.load();
  }

  Future<void> loadMoegirl() async {
    if (!moegirl.loading) await moegirl.load();
  }

  @override
  void dispose() {
    for (final section in _sections) {
      section.removeListener(notifyListeners);
      section.dispose();
    }
    super.dispose();
  }
}

Future<SubjectMetadata> _loadMetadata(BangumiApi api, int id) async {
  var failed = false;
  Future<List<T>> guarded<T>(Future<List<T>> Function() request) async {
    try {
      return List.unmodifiable(await request());
    } catch (_) {
      failed = true;
      return const [];
    }
  }

  final characters = guarded(() => api.getSubjectCharacters(id));
  final persons = guarded(() => api.getSubjectPersons(id));
  final related = guarded(() => api.getRelatedSubjects(id));
  final result = await (characters, persons, related).wait;
  return SubjectMetadata(
    characters: result.$1,
    persons: result.$2,
    related: result.$3,
    warning: failed ? '部分关联信息加载失败' : null,
  );
}

String _historyErrorMessage(Object error) {
  if (error is NetabaApiException) return error.message;
  if (error is DioException && error.error is NetabaApiException) {
    return (error.error as NetabaApiException).message;
  }
  final match = RegExp(
    r'NetabaApiException[:\s]*([^\n]+)',
  ).firstMatch(error.toString());
  return match?.group(1)?.trim() ?? '获取评分历史失败';
}
