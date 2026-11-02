import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/user_biography.dart';
import 'package:mubangumi/widgets/community_rich_content.dart';
import 'package:mubangumi/widgets/biography_dialog.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:flutter/gestures.dart';

void main() {
  test(
    'biography destinations resolve relative URLs and honor image routing',
    () {
      BangumiEndpoints.setRoute(BangumiNetworkRoute.reverseProxy);
      addTearDown(
        () => BangumiEndpoints.setRoute(BangumiNetworkRoute.official),
      );
      expect(biographyUri('/subject/1').toString(), 'https://bgm.tv/subject/1');
      expect(
        communityContentUri(
          '//lain.bgm.tv/pic/cover/l/a.jpg',
          image: true,
        ).toString(),
        'https://bgmimg.anibt.net/pic/cover/l/a.jpg',
      );
      for (final url in [
        'javascript:alert(1)',
        'file:///x',
        'https://user:pass@example.com',
      ]) {
        expect(biographyUri(url), isNull);
      }
    },
  );
  testWidgets(
    'Markdown-like biography text keeps BBCode, newlines, and safe links',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BiographyContent(
              '- **列表** |\r\n[color=red][u]红字[/u][/color]\n[size=20]大字[/size]\n[quote]引用[/quote]\n[url]/subject/1[/url]\nhttps://bgm.tv/subject/2\n[b][i]交叉[/b][/i]\n(bgm38)\n[mask]隐藏[/mask]',
            ),
          ),
        ),
      );
      final texts = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      final plain = texts
          .map((text) => text.textSpan?.toPlainText() ?? text.data ?? '')
          .join();
      expect(plain, contains('- **列表** |\n'));
      expect(plain, contains('交叉'));
      expect(plain, isNot(contains('[/b]')));
      expect(plain, isNot(contains('[color')));
      expect(plain, isNot(contains('隐藏')));
      Iterable<TextSpan> spans(InlineSpan span) sync* {
        if (span is TextSpan) {
          yield span;
          for (final child in span.children ?? <InlineSpan>[]) {
            yield* spans(child);
          }
        }
      }

      final all = texts.expand(
        (text) => text.textSpan == null ? <TextSpan>[] : spans(text.textSpan!),
      );
      expect(
        all.any(
          (span) =>
              span.style?.color == const Color(0xffff0000) &&
              span.style?.decoration == TextDecoration.underline,
        ),
        isTrue,
      );
      expect(
        all.where((span) => span.recognizer is TapGestureRecognizer),
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('biography preview skips leading empty lines', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userBiographyProvider(
            'alice',
          ).overrideWith((ref) async => '\r\n  \n[b]第一行[/b]\n第二行'),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UserBiography(username: 'alice')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一行'), findsOneWidget);
  });
  testWidgets(
    'public bio is shown separately from signatures and mask preview stays folded',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userBiographyProvider(
              'alice',
            ).overrideWith((ref) async => '[b]喜欢动漫与音乐[/b]\n[mask]隐藏的剧透[/mask]'),
          ],
          child: const MaterialApp(
            home: Scaffold(body: UserBiography(username: 'alice')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('展开'), findsOneWidget);
      expect(find.textContaining('喜欢动漫与音乐'), findsOneWidget);
      expect(find.textContaining('隐藏的剧透'), findsNothing);
      expect(find.textContaining('[折叠内容]'), findsNothing);
      expect(tester.widget<Text>(find.text('喜欢动漫与音乐')).maxLines, 1);
      await tester.tap(find.text('展开'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityRichContent), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
