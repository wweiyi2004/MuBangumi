import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/account_content_preferences.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/widgets/account_content_preferences_tile.dart';

const disabled = AccountContentPreferences(
  showNsfwSubject: false,
  canSetNsfwSubject: true,
  allowNsfw: false,
);
const enabled = AccountContentPreferences(
  showNsfwSubject: true,
  canSetNsfwSubject: true,
  allowNsfw: true,
);
Map<String, dynamic> response(bool enabled) => {
  'settings': {'privateMessage': 'friends'},
  'preferences': {
    'showNsfwSubject': enabled,
    'canSetNsfwSubject': true,
    'allowNsfw': enabled,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'privacy server errors preserve HTTP status and do not retry writes',
    () async {
      var calls = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              calls++;
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: request,
                    statusCode: 500,
                    data: {'message': 'internal error'},
                  ),
                ),
              );
            },
          ),
        );
      final service = CommunityService.test(p1Dio: dio)
        ..setAccessToken('test')
        ..setCurrentUsername('alice');
      await expectLater(
        service.setNsfwPreference(true),
        throwsA(
          isA<AccountContentPreferencesException>().having(
            (e) => e.statusCode,
            'HTTP status',
            500,
          ),
        ),
      );
      expect(calls, 1);
      expect(service.contentPreferencesChanges.value, 0);
    },
  );

  testWidgets(
    'server failure exposes website fallback and verifies the setting on return',
    (tester) async {
      final service = _Service();
      var websiteOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountContentPreferencesTile(
              service: service,
              onOpenWebsite: () async {
                websiteOpened = true;
                service.value = enabled;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      service.save.completeError(const AccountContentPreferencesException(500));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(find.textContaining('账号权限受限'), findsNothing);
      await tester.tap(find.text('在官网设置受限内容'));
      await tester.pumpAndSettle();
      expect(websiteOpened, isTrue);
      expect(service.refreshes, 1);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(service.writes, [true]);
    },
  );

  testWidgets('a response with the old preference does not claim success', (
    tester,
  ) async {
    final service = _Service();
    await _show(tester, service);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    service.save.complete(disabled);
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未确认这次变更'), findsOneWidget);
    expect(find.textContaining('已保存到 Bangumi'), findsNothing);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });

  testWidgets(
    'closing the website without saving keeps the authoritative off state',
    (tester) async {
      final service = _Service();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountContentPreferencesTile(
              service: service,
              onOpenWebsite: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('在官网设置受限内容'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(service.writes, isEmpty);
    },
  );
  test(
    'reads uncached preferences and patches only the NSFW preference',
    () async {
      final requests = <RequestOptions>[];
      var current = false;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              requests.add(request);
              if (request.method == 'PATCH') {
                current =
                    request.data['preferences']['showNsfwSubject'] as bool;
              }
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 200,
                  data: response(current),
                ),
              );
            },
          ),
        );
      final service = CommunityService.test(p1Dio: dio)
        ..setAccessToken('test')
        ..setCurrentUsername('alice');
      expect((await service.loadContentPreferences()).showNsfwSubject, isFalse);
      current = true;
      expect((await service.loadContentPreferences()).showNsfwSubject, isTrue);
      expect((await service.setNsfwPreference(false)).showNsfwSubject, isFalse);
      expect(requests.map((r) => r.method), ['GET', 'GET', 'PATCH']);
      expect(requests.last.path, '/p1/privacy');
      expect(requests.last.data, {
        'preferences': {'showNsfwSubject': false},
      });
      expect(service.contentPreferencesChanges.value, 1);
    },
  );

  test(
    'changing accounts during 401 refresh cannot patch the replacement account',
    () async {
      var calls = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              calls++;
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: request,
                    statusCode: 401,
                    data: {'error': 'TOKEN_INVALID'},
                  ),
                ),
              );
            },
          ),
        );
      final service = CommunityService.test(p1Dio: dio)
        ..setAccessToken('old')
        ..setCurrentUsername('alice');
      service.onUnauthorizedRefresh = () async {
        service.setCurrentUsername('bob');
        service.setAccessToken('replacement');
        return true;
      };
      await expectLater(
        service.setNsfwPreference(true),
        throwsA(isA<FormatException>()),
      );
      expect(calls, 1);
      expect(service.contentPreferencesChanges.value, 0);
    },
  );

  test(
    'old timeline cannot restore pre-change content after a saved preference',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var timelineCalls = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) async {
              if (request.path.contains('timeline')) {
                if (timelineCalls++ == 0) {
                  entered.complete();
                  await release.future;
                }
                handler.resolve(
                  Response(
                    requestOptions: request,
                    statusCode: 200,
                    data: <dynamic>[],
                  ),
                );
              } else {
                handler.resolve(
                  Response(
                    requestOptions: request,
                    statusCode: 200,
                    data: response(true),
                  ),
                );
              }
            },
          ),
        );
      final service = CommunityService.test(p1Dio: dio)
        ..setAccessToken('test')
        ..setCurrentUsername('alice');
      final stale = service.loadTimeline(CommunityTimelineMode.me);
      await entered.future;
      await service.setNsfwPreference(true);
      final rejected = expectLater(stale, throwsA(isA<FormatException>()));
      release.complete();
      await rejected;
      await service.loadTimeline(CommunityTimelineMode.me);
      expect(timelineCalls, 2);
    },
  );

  test('incomplete settings are not interpreted as a disabled preference', () {
    expect(
      () => AccountContentPreferences.fromJson({'preferences': {}}),
      throwsFormatException,
    );
  });

  testWidgets(
    'switch waits for server acknowledgement and blocks duplicate writes',
    (tester) async {
      final service = _Service();
      await _show(tester, service);
      final toggle = find.byType(SwitchListTile);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      expect(service.writes, [true]);
      service.save.complete(enabled);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    },
  );

  testWidgets(
    'permission denied keeps switch disabled and explains eligibility',
    (tester) async {
      final service = _Service()
        ..value = const AccountContentPreferences(
          showNsfwSubject: false,
          canSetNsfwSubject: false,
          allowNsfw: false,
        );
      await _show(tester, service);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(find.textContaining('60 天'), findsOneWidget);
      expect(service.writes, isEmpty);
    },
  );

  testWidgets('a failed save preserves old state until the user reads again', (
    tester,
  ) async {
    final service = _Service();
    await _show(tester, service);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    service.save.completeError(Exception('network'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    service.value =
        enabled; // The server may have committed despite the lost response.
    await tester.tap(find.text('重新读取设置'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });

  testWidgets('late save cannot update a replacement account', (tester) async {
    final service = _Service();
    await _show(tester, service);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    service.setCurrentUsername('bob');
    await tester.pumpAndSettle();
    service.save.complete(enabled);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.textContaining('已保存到 Bangumi'), findsNothing);
  });

  testWidgets('read failure has no misleading off switch and allows retry', (
    tester,
  ) async {
    final service = _Service()..readFails = true;
    await _show(tester, service);
    expect(find.byType(SwitchListTile), findsNothing);
    service.readFails = false;
    await tester.tap(find.text('重新读取设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsOneWidget);
  });
}

Future<void> _show(WidgetTester tester, _Service service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AccountContentPreferencesTile(service: service)),
    ),
  );
  await tester.pumpAndSettle();
}

class _Service extends CommunityService {
  _Service() : super.test() {
    setAccessToken('test');
    setCurrentUsername('alice');
  }
  AccountContentPreferences value = disabled;
  bool readFails = false;
  final save = Completer<AccountContentPreferences>();
  final writes = <bool>[];
  int refreshes = 0;
  @override
  Future<void> refreshContentAfterPreferenceChange() async {
    refreshes++;
  }

  @override
  Future<AccountContentPreferences> loadContentPreferences() async {
    if (readFails) throw Exception('offline');
    return value;
  }

  @override
  Future<AccountContentPreferences> setNsfwPreference(bool enabled) {
    writes.add(enabled);
    return save.future;
  }
}
