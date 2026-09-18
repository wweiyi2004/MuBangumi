import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/core/network/moegirl_service.dart';
import 'package:mubangumi/core/network/netaba_api.dart';
import 'package:mubangumi/features/subject_detail/application/subject_detail_resource.dart';
import 'package:mubangumi/features/subject_detail/application/subject_supplement_controller.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/models/netaba_models.dart';

import 'support/progress_fixtures.dart';

void main() {
  for (final oldFails in [false, true]) {
    test(
      'a late section ${oldFails ? 'error' : 'value'} cannot replace its retry',
      () async {
        final requests = <Completer<int>>[];
        final resource = SubjectDetailResource<int>(
          initial: 0,
          request: () {
            final result = Completer<int>();
            requests.add(result);
            return result.future;
          },
          errorMessage: (_) => 'failed',
        );
        addTearDown(resource.dispose);
        final old = resource.load();
        final current = resource.load();
        requests.last.complete(2);
        await current;
        if (oldFails) {
          requests.first.completeError(Exception('old'));
        } else {
          requests.first.complete(1);
        }
        await old;
        expect(resource.value, 2);
        expect(resource.error, isNull);
        expect(resource.loading, isFalse);
      },
    );
  }

  test(
    'failed reload preserves usable content and clears error on retry',
    () async {
      var fail = true;
      final resource = SubjectDetailResource<int>(
        initial: 7,
        request: () async {
          if (fail) throw Exception('offline');
          return 8;
        },
        errorMessage: (_) => 'failed',
      );
      addTearDown(resource.dispose);
      await resource.load();
      expect(resource.value, 7);
      expect(resource.error, 'failed');
      fail = false;
      final retry = resource.load();
      expect(resource.error, isNull);
      await retry;
      expect(resource.value, 8);
    },
  );

  test('disposed section never publishes a late answer', () async {
    final result = Completer<int>();
    final resource = SubjectDetailResource<int>(
      initial: 0,
      request: () => result.future,
      errorMessage: (_) => 'failed',
    );
    var notifications = 0;
    resource.addListener(() => notifications++);
    final load = resource.load();
    resource.dispose();
    result.complete(1);
    await load;
    expect(notifications, 1);
  });

  test(
    'partial metadata failure preserves other sections and retry clears warning',
    () async {
      final api = _Api()..failPersons = true;
      final controller = _controller(api);
      addTearDown(controller.dispose);
      await controller.metadata.load();
      expect(controller.metadata.value.characters.single.id, 2);
      expect(controller.metadata.value.persons, isEmpty);
      expect(controller.metadata.value.warning, '部分关联信息加载失败');
      api.failPersons = false;
      await controller.metadata.load();
      expect(controller.metadata.value.warning, isNull);
      expect(controller.metadata.error, isNull);
    },
  );

  test(
    'slow topics and failed history do not block fresh details and metadata',
    () async {
      final topics = Completer<List<CommunityTopic>>();
      final controller = SubjectSupplementController(
        subject: progressCollection(1).subject,
        api: () => _Api(),
        loadTopics: (_) => topics.future,
        loadHistory: (_) async => throw DioException(
          requestOptions: RequestOptions(path: '/history'),
          error: const NetabaApiException('history unavailable'),
        ),
        findMoegirl: (_, {required forceRefresh}) async => null,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await Future<void>.delayed(Duration.zero);
      expect(controller.details.value.id, 3);
      expect(controller.metadata.value.characters.single.id, 2);
      expect(controller.topics.loading, isTrue);
      expect(controller.history.error, 'history unavailable');
      expect(controller.moegirl.attempted, isFalse);
      topics.complete([]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.topics.loading, isFalse);
    },
  );

  test(
    'Moegirl stays lazy, merges current subject and forces only later retries',
    () async {
      final flags = <bool>[];
      final names = <String>[];
      final requests = <Completer<MoegirlEntry?>>[];
      final controller = _controller(
        _Api(),
        findMoegirl: (subject, {required forceRefresh}) {
          flags.add(forceRefresh);
          names.add(subject.name);
          final result = Completer<MoegirlEntry?>();
          requests.add(result);
          return result.future;
        },
      );
      addTearDown(controller.dispose);
      await controller.details.load();
      expect(flags, isEmpty);
      final first = controller.loadMoegirl();
      await controller.loadMoegirl();
      expect(flags, [false]);
      requests.single.complete(null);
      await first;
      final retry = controller.loadMoegirl();
      requests.last.complete(null);
      await retry;
      expect(flags, [false, true]);
      expect(names, ['作品3', '作品3']);
    },
  );
}

SubjectSupplementController _controller(
  _Api api, {
  Future<MoegirlEntry?> Function(Subject, {required bool forceRefresh})?
  findMoegirl,
}) => SubjectSupplementController(
  subject: progressCollection(1).subject,
  api: () => api,
  loadHistory: (_) async => const NetabaSubjectHistory(
    subject: NetabaSubjectInfo(name: 'subject', nameCn: ''),
    history: [],
  ),
  loadTopics: (_) async => [],
  findMoegirl: findMoegirl ?? (_, {required forceRefresh}) async => null,
);

class _Api extends BangumiApi {
  bool failPersons = false;
  @override
  Future<Subject> getSubject(int subjectId) async =>
      progressCollection(3).subject;
  @override
  Future<List<SubjectCharacter>> getSubjectCharacters(int subjectId) async => [
    const SubjectCharacter(
      id: 2,
      name: 'character',
      nameCn: '',
      imageUrl: '',
      relation: '',
      actors: [],
    ),
  ];
  @override
  Future<List<SubjectPerson>> getSubjectPersons(int subjectId) async {
    if (failPersons) throw Exception('offline');
    return [];
  }

  @override
  Future<List<RelatedSubject>> getRelatedSubjects(int subjectId) async => [];
}
