import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/screens/community_page.dart';
import 'package:mubangumi/screens/website_login_screen.dart';
import 'package:mubangumi/state/account_access_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'support/pm_fixtures.dart';

class Access extends AccountAccessController {
  Access(WebsiteSessionController website, PmTestSession session)
    : super(website: website, currentUser: () => session.state.user);
  final snapshot = Completer<WebsiteSessionSnapshot>();
  int checks = 0;
  @override
  Future<bool> verify({bool force = false}) async => true;
  @override
  Future<WebsiteSessionSnapshot> requireWebsiteSession() {
    checks++;
    return snapshot.future;
  }
}

void main() {
  testWidgets(
    'website navigation cannot inject cookies after its account changes',
    (tester) async {
      final store = PmTestWebsiteStore();
      final website = WebsiteSessionController(store);
      final session = PmTestSession();
      final access = Access(website, session);
      access.accountChanged(session.state.user);
      addTearDown(access.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountAccessProvider.overrideWithValue(access),
            websiteSessionProvider.overrideWith((ref) => website),
            sessionProvider.overrideWith((ref) => session),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => openSeededCommunityWeb(
                    context,
                    initialUrl: 'https://bgm.tv/pm',
                    title: 'fixture',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(access.checks, 1);
      session.switchUser(2);
      access.accountChanged(session.state.user);
      access.snapshot.complete((await store.read())!);
      await tester.pumpAndSettle();
      expect(find.byType(CommunityWebScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
