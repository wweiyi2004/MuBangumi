import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/features/subject_detail/presentation/subject_episode_grid.dart';
import 'package:mubangumi/features/subject_detail/presentation/subject_meta_sections.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  testWidgets(
    'extracted episode grid retains paging and watched-state callbacks',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final taps = <(int, bool)>[];
      await tester.pumpWidget(
        AppRouteScope(
          resolve: AppRouter.resolve,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SubjectEpisodeGrid(
                  episodes: [
                    for (int id = 1; id <= 70; id++)
                      Episode.fromJson({
                        'id': id,
                        'type': 0,
                        'sort': id,
                        'name': '章节$id',
                      }),
                  ],
                  episodeTypes: const {1: 2},
                  updatingEpisodes: const {2},
                  enabled: true,
                  onTap: (episode, watched) => taps.add((episode.id, watched)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('章节1'));
      expect(taps, [(1, true)]);
      final savingButton = find.descendant(
        of: find.byTooltip('章节2'),
        matching: find.byType(OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(savingButton).onPressed, isNull);
      expect(find.byTooltip('章节70'), findsNothing);
      final more = find.text('继续显示（60 / 70）');
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      final last = find.byTooltip('章节70');
      await tester.ensureVisible(last);
      await tester.tap(last);
      expect(taps.last, (70, false));
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'metadata sections preserve navigation callbacks at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final opened = <int>[];
        await tester.pumpWidget(
          AppRouteScope(
            resolve: AppRouter.resolve,
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      SubjectCharacterRail(
                        characters: const [
                          SubjectCharacter(
                            id: 1,
                            name: '测试角色',
                            nameCn: '',
                            imageUrl: '',
                            relation: '主角',
                            actors: [],
                          ),
                        ],
                        onOpen: (character) => opened.add(character.id),
                      ),
                      SubjectStaffRoleGroups(
                        people: const [
                          SubjectPerson(
                            id: 2,
                            name: '测试制作人',
                            nameCn: '',
                            imageUrl: '',
                            relation: '监督',
                            career: [],
                          ),
                        ],
                        onOpen: (person) => opened.add(person.id),
                      ),
                      SubjectRelatedRail(
                        subjects: const [
                          RelatedSubject(
                            id: 3,
                            name: '关联作品',
                            nameCn: '',
                            imageUrl: '',
                            relation: '续集',
                            type: SubjectType.anime,
                          ),
                        ],
                        onOpen: (subject) => opened.add(subject.id),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final name in ['测试角色', '测试制作人', '关联作品']) {
          final target = find.text(name);
          await tester.ensureVisible(target);
          await tester.tap(target);
        }
        expect(opened, [1, 2, 3]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
