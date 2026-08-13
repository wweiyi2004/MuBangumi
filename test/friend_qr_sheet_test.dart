import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/widgets/friend_qr_actions.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('shows a client-only friend QR for the signed-in user', (
    tester,
  ) async {
    const user = BangumiUser(
      id: 1,
      username: 'wweiyi',
      nickname: '维依',
      avatarUrl: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMyFriendQr(context, user),
              child: const Text('open-qr'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-qr'));
    await tester.pumpAndSettle();

    expect(find.text('我的二维码'), findsOneWidget);
    expect(find.text('@wweiyi'), findsOneWidget);
    expect(find.text('仅限 MuBangumi 扫描添加好友'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });
}
