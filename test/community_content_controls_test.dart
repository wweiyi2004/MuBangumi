import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/community_widgets.dart';

void main() {
  testWidgets('long community content can expand and collapse', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollapsibleCommunityText(List.filled(800, 'a').join()),
        ),
      ),
    );

    expect(find.text('展开全文'), findsOneWidget);
    await tester.tap(find.text('展开全文'));
    await tester.pump();
    expect(find.text('收起长内容'), findsOneWidget);
  });

  testWidgets('blocked content is recoverably folded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BlockedCommunityContent(
            username: 'alice',
            blocked: true,
            child: Text('hidden post'),
          ),
        ),
      ),
    );

    expect(find.text('hidden post'), findsNothing);
    expect(find.text('已折叠 @alice 的内容'), findsOneWidget);
    await tester.tap(find.text('临时查看'));
    await tester.pump();
    expect(find.text('hidden post'), findsOneWidget);
  });
}
