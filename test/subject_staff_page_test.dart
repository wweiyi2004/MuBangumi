import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/screens/subject_staff_page.dart';

void main() {
  testWidgets(
    'staff page groups every role and searches without leaving the subject',
    (tester) async {
      const person = SubjectPerson(
        id: 7,
        name: 'Director',
        nameCn: '导演甲',
        imageUrl: '',
        relation: '监督',
        career: [],
      );
      const second = SubjectPerson(
        id: 8,
        name: 'Artist',
        nameCn: '原画乙',
        imageUrl: '',
        relation: '原画',
        career: [],
      );
      PersonRoute? opened;
      await tester.pumpWidget(
        ProviderScope(
          child: AppRouteScope(
            resolve: (route) {
              opened = route as PersonRoute;
              return Scaffold(appBar: AppBar(title: Text(opened!.seedName)));
            },
            child: MaterialApp(
              home: SubjectStaffPage(
                subject: Subject.fromJson({'id': 42, 'name_cn': '测试作品'}),
                seed: const [person, second],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('监督 · 1 位'), findsOneWidget);
      expect(find.text('原画 · 1 位'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '原画');
      await tester.pump();
      expect(find.text('导演甲'), findsNothing);
      expect(find.text('原画乙'), findsOneWidget);
      await tester.tap(find.text('原画乙'));
      await tester.pumpAndSettle();
      expect(opened?.personId, 8);
      expect(tester.takeException(), isNull);
    },
  );
}
