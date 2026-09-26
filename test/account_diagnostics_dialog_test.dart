import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/diagnostics/account_diagnostics.dart';
import 'package:mubangumi/core/update/app_update_service.dart';
import 'package:mubangumi/core/update/github_release_store.dart';
import 'package:mubangumi/state/account_diagnostics_provider.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/update_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'package:mubangumi/widgets/account_diagnostics_dialog.dart';
import 'support/pm_fixtures.dart';

const version = AppUpdateSnapshot(
  phase: AppUpdatePhase.unavailable,
  appVersion: '2.3.1',
  buildNumber: '4029',
  currentPatch: 11,
);

class VersionService extends AppUpdateService {
  @override
  Future<AppUpdateSnapshot> readInstalledVersion() async => version;
}

class Updates extends UpdateController {
  Updates() : super(VersionService(), GithubReleaseSkipStore()) {
    state = const UpdateUiState(snapshot: version);
  }
}

void main() {
  testWidgets(
    'phone diagnostic preview copies only its reviewed snapshot and can be cleared',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? clipboard;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final diagnostics = AccountDiagnostics()
        ..record(
          AccountArea.privateMessages,
          AccountEvent.requestFailed,
          status: 503,
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountDiagnosticsProvider.overrideWithValue(diagnostics),
            sessionProvider.overrideWith((ref) => PmTestSession()),
            websiteSessionProvider.overrideWith(
              (ref) => WebsiteSessionController(PmTestWebsiteStore()),
            ),
            updateControllerProvider.overrideWith((ref) => Updates()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AccountDiagnosticsDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(clipboard, contains('"version": "2.3.1"'));
      expect(clipboard, contains('"patch": 11'));
      expect(clipboard, contains('503'));
      expect(clipboard, isNot(contains('account-a')));
      expect(clipboard, isNot(contains('user1')));
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(diagnostics.events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
