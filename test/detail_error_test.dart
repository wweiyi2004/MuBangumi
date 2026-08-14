import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/screens/character_detail_screen.dart';
import 'package:mubangumi/screens/person_detail_screen.dart';
import 'package:mubangumi/state/session_controller.dart';

void main() {
  testWidgets('character detail failure leaves loading state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bangumiApiProvider.overrideWithValue(_FailingDetailBangumiApi()),
        ],
        child: const MaterialApp(home: CharacterDetailScreen(characterId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('角色加载失败'), findsOneWidget);
    expect(find.text('角色接口不可用'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('person detail failure leaves loading state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bangumiApiProvider.overrideWithValue(_FailingDetailBangumiApi()),
        ],
        child: const MaterialApp(home: PersonDetailScreen(personId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('人物加载失败'), findsOneWidget);
    expect(find.text('人物接口不可用'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _FailingDetailBangumiApi extends BangumiApi {
  @override
  Future<CharacterDetail> getCharacter(int characterId) =>
      Future.error(Exception('角色接口不可用'));

  @override
  Future<List<MonoLinkedSubject>> getCharacterSubjects(int characterId) async =>
      const [];

  @override
  Future<List<MonoLinkedPerson>> getCharacterPersons(int characterId) async =>
      const [];

  @override
  Future<PersonDetail> getPerson(int personId) =>
      Future.error(Exception('人物接口不可用'));

  @override
  Future<List<MonoLinkedSubject>> getPersonSubjects(int personId) async =>
      const [];

  @override
  Future<List<MonoLinkedCharacter>> getPersonCharacters(int personId) async =>
      const [];
}
