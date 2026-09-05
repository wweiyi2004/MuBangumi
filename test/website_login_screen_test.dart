import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/screens/website_login_screen.dart';

void main() {
  testWidgets('cookie load failure shows retry instead of spinning forever', (
    tester,
  ) async {
    var calls = 0;
    Future<List<WebsiteCookie>> loadCookies() async {
      calls++;
      throw Exception('secure storage unavailable');
    }

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: WebsiteLoginScreen(cookieLoader: loadCookies)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法读取网站登录，请重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
