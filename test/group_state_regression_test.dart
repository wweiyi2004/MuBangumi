import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/network/community_p1_parser.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const group = {
  'id': 7,
  'name': 'demo',
  'title': '测试小组',
  'accessible': false,
  'membership': {'uid': 101, 'role': 1, 'joinedAt': 0},
};

void main() {
  late Database db;
  late CommunityCache cache;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE community_cache (cache_key TEXT PRIMARY KEY, payload TEXT, updated_at INTEGER, account_scoped INTEGER)',
    );
    cache = CommunityCache.test(connection: db);
  });
  tearDown(() => db.close());

  CommunityService serviceFor(
    FutureOr<Map<String, dynamic>> Function(RequestOptions) respond,
  ) {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            try {
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 200,
                  data: await respond(request),
                ),
              );
            } on DioException catch (error) {
              handler.reject(error);
            }
          },
        ),
      );
    final service = CommunityService.test(p1Dio: dio, cache: cache)
      ..setCurrentUsername('alice')
      ..setAccessToken('fixture');
    addTearDown(service.dispose);
    return service;
  }

  test(
    'membership refresh supersedes an older in-flight membership read',
    () async {
      final old = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      var reads = 0;
      final service = serviceFor((request) {
        if (++reads == 1) {
          started.complete();
          return old.future;
        }
        return {...group, 'membership': null};
      });
      final pending = service.loadGroupPreview('demo');
      await started.future;
      service.invalidateGroupMembership();
      final fresh = await service.loadGroupPreview('demo');
      expect(fresh.isJoined, false);
      final assertion = expectLater(pending, throwsA(isA<FormatException>()));
      old.complete(Map.from(group));
      await assertion;
      expect(reads, 2);
    },
  );

  test('membership survives a missing join timestamp', () {
    final detail = CommunityP1Parser().parseGroupDetail(Map.from(group));
    expect(detail.isJoined, true);
    expect(detail.canCreateTopic, true);
    expect(detail.joinedAt, isNull);
    expect(detail.membershipRole, CommunityGroupRole.creator);
    expect(detail.canManage, true);
  });

  test('moderators retain their management identity without a join date', () {
    final detail = CommunityP1Parser().parseGroupDetail({
      ...group,
      'membership': {'uid': 101, 'role': 2},
    });
    expect(detail.isJoined, true);
    expect(detail.canManage, true);
    expect(detail.membershipLabel, '管理员');
    expect(detail.canCreateTopic, true);
  });

  test('blocked role cannot offer posting even in an open group', () {
    final detail = CommunityP1Parser().parseGroupDetail({
      ...group,
      'accessible': true,
      'membership': {'uid': 101, 'role': 3, 'joinedAt': 1785980000},
    });
    expect(detail.canManage, false);
    expect(detail.canCreateTopic, false);
  });

  test('management identity is not inferred from an unbound role field', () {
    final detail = CommunityP1Parser().parseGroupDetail({
      ...group,
      'membership': {'role': 1},
    });
    expect(detail.canManage, false);
    expect(detail.membershipRole, isNull);
  });

  for (final failedRole in [1, 2]) {
    test(
      'a failed management role $failedRole preserves the other role',
      () async {
        final service = serviceFor((request) {
          if (request.path.endsWith('/members')) {
            final role = request.queryParameters['role'];
            if (role == failedRole) {
              throw DioException(
                requestOptions: request,
                type: DioExceptionType.badResponse,
                response: Response(requestOptions: request, statusCode: 403),
              );
            }
            return {
              'data': [
                if (role != 0)
                  {
                    'user': {
                      'id': role,
                      'username': 'role$role',
                      'nickname': 'role$role',
                    },
                  },
              ],
            };
          }
          return request.path.endsWith('/topics')
              ? {'data': []}
              : Map.from(group);
        });
        final detail = await service.loadGroupDetail('demo');
        expect(detail.moderators.single.id, failedRole == 1 ? 2 : 1);
        expect(detail.canManage, true);
        expect(detail.unavailableSections, {CommunityGroupSection.moderators});
      },
    );
  }

  test(
    'losing API authorization during a managed-group request discards its response',
    () async {
      final ready = Completer<void>();
      final result = Completer<Map<String, dynamic>>();
      final service = serviceFor((request) {
        ready.complete();
        return result.future;
      });
      final pending = service.loadGroupPage(mode: CommunityGroupMode.managed);
      await ready.future;
      service.setAccessToken(null);
      final assertion = expectLater(pending, throwsException);
      result.complete({
        'data': [group],
        'total': 1,
      });
      await assertion;
    },
  );

  test('management team includes both creator and moderator roles', () async {
    final roles = <int>[];
    final service = serviceFor((request) {
      if (request.path.endsWith('/members')) {
        final role = request.queryParameters['role'] as int;
        roles.add(role);
        return {
          'data': [
            if (role > 0)
              {
                'user': {
                  'id': role,
                  'username': 'role$role',
                  'nickname': 'role$role',
                },
              },
          ],
        };
      }
      return request.path.endsWith('/topics') ? {'data': []} : Map.from(group);
    });
    final detail = await service.loadGroupDetail('demo');
    expect(detail.moderators.map((member) => member.username), [
      'role1',
      'role2',
    ]);
    expect(roles.toSet(), {0, 1, 2});
  });

  for (final role in [-2, -1, 3, 99]) {
    test('inactive role $role is not an active group membership', () {
      final detail = CommunityP1Parser().parseGroupDetail({
        ...group,
        'membership': {'uid': 101, 'role': role, 'joinedAt': 1785980000},
      });
      expect(detail.isJoined, false);
      expect(detail.canCreateTopic, false);
    });
  }

  test(
    'managed filter never falls through to anonymous public groups',
    () async {
      var requests = 0;
      final service = serviceFor((request) {
        requests++;
        return {
          'data': [group],
          'total': 1,
        };
      })..setAccessToken(null);
      await expectLater(
        service.loadGroupPage(mode: CommunityGroupMode.managed),
        throwsException,
      );
      expect(requests, 0);
      expect(
        await service.readCachedGroups(
          CommunityGroupMode.managed,
          CommunityGroupSort.members,
        ),
        isNull,
      );
    },
  );

  test(
    'optional member failure preserves group membership and topics',
    () async {
      final service = serviceFor((request) {
        if (request.path.endsWith('/members')) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: request, statusCode: 403),
          );
        }
        return request.path.endsWith('/topics')
            ? {
                'data': [
                  {'id': 42, 'title': '可用的话题'},
                ],
                'total': 1,
              }
            : Map.from(group);
      });
      final detail = await service.loadGroupDetail('demo');
      expect(detail.isJoined, true);
      expect(detail.recentTopics.single.id, 42);
      expect(detail.unavailableSections, {
        CommunityGroupSection.members,
        CommunityGroupSection.moderators,
      });
      expect(
        (await service.readCachedGroupDetail('demo'))!.unavailableSections,
        detail.unavailableSections,
      );
    },
  );

  test(
    'group detail from an old account cannot escape the service boundary',
    () async {
      final delayed = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      final service = serviceFor((request) {
        if (request.path.endsWith('/demo')) {
          started.complete();
          return delayed.future;
        }
        return {'data': [], 'total': 0};
      });
      final request = service.loadGroupDetail('demo');
      await started.future;
      service.setCurrentUsername('bob');
      final assertion = expectLater(request, throwsA(isA<FormatException>()));
      delayed.complete(Map.from(group));
      await assertion;
      expect(await service.readCachedGroupDetail('demo'), isNull);
    },
  );

  test(
    'group list pagination advances by raw server rows, not parsed groups',
    () async {
      final service = serviceFor(
        (request) => {
          'data': [
            group,
            {'id': 0, 'title': 'invalid'},
          ],
          'total': 3,
        },
      );
      final page = await service.loadGroupPage(mode: CommunityGroupMode.joined);
      expect(page.data, hasLength(1));
      expect(page.rawCount, 2);
      expect(
        (await service.readCachedGroups(
          CommunityGroupMode.joined,
          CommunityGroupSort.members,
        ))!.rawCount,
        2,
      );
    },
  );
}
