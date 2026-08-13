import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_smiles.dart';
import 'package:mubangumi/widgets/community_widgets.dart';

void main() {
  test('maps official (bgm43) TV smiles to the Cinnamor pack', () {
    expect(
      BangumiSmiles.imageUrl('(bgm43)'),
      'https://lain.bgm.tv/img/smiles/tv/20.gif',
    );
    expect(
      BangumiSmiles.imageUrl('(BGM43)'),
      'https://lain.bgm.tv/img/smiles/tv/20.gif',
    );
  });

  test('maps the other official (bgm) ranges', () {
    expect(
      BangumiSmiles.imageUrl('(bgm01)'),
      'https://lain.bgm.tv/img/smiles/bgm/01.png',
    );
    expect(
      BangumiSmiles.imageUrl('(bgm11)'),
      'https://lain.bgm.tv/img/smiles/bgm/11.gif',
    );
    expect(
      BangumiSmiles.imageUrl('(bgm24)'),
      'https://lain.bgm.tv/img/smiles/tv/01.gif',
    );
    expect(
      BangumiSmiles.imageUrl('(bgm200)'),
      'https://lain.bgm.tv/img/smiles/tv_vs/bgm_200.png',
    );
    expect(BangumiSmiles.imageUrl('(bgm999)'), isNull);
    expect(BangumiSmiles.imageUrl('bgm43'), isNull);
  });

  test('splits mixed text and smile tokens', () {
    final parts = BangumiSmiles.split('(bgm43)你好(bgm01)');
    expect(parts, hasLength(3));
    expect(parts[0].imageUrl, contains('/tv/20.gif'));
    expect(parts[1].text, '你好');
    expect(parts[2].imageUrl, contains('/bgm/01.png'));
  });

  test('maps API reaction values to the official visible smiles', () {
    expect(BangumiReactions.options, hasLength(12));
    expect(BangumiReactions.optionFor(0)?.token, '(bgm67)');
    expect(BangumiReactions.optionFor(54)?.token, '(bgm38)');
    expect(BangumiReactions.optionFor(90)?.token, '(bgm74)');
    expect(BangumiReactions.accepts(999), isFalse);
  });

  testWidgets('community text renders (bgm43) as images instead of raw codes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CollapsibleCommunityText('(bgm43)(bgm43)(bgm43)')),
      ),
    );

    expect(find.text('(bgm43)(bgm43)(bgm43)'), findsNothing);
    expect(find.byType(Image), findsNWidgets(3));
  });
}
