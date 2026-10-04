import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/user_biography.dart';
import 'package:mubangumi/widgets/community_rich_content.dart';

void main() {
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
