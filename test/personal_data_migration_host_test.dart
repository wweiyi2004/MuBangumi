import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/personal_data_migration_host.dart';

void main() {
  testWidgets(
    'legacy location choice blocks account startup and fits large phone text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        PersonalDataMigrationHost(
          enabled: true,
          prepare: () async => false,
          child: const Text('account providers started'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('选择旧程序目录并迁移'));
      await tester.pumpAndSettle();
      expect(find.text('account providers started'), findsNothing);
      expect(find.text('选择旧程序目录并迁移').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('a prepared data directory proceeds to the application', (
    tester,
  ) async {
    await tester.pumpWidget(
      PersonalDataMigrationHost(
        enabled: true,
        prepare: () async => true,
        child: const MaterialApp(home: Text('account providers started')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('account providers started'), findsOneWidget);
  });
}
