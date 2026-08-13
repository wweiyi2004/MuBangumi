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
    expect(find.text('保存图片'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
  });

  testWidgets('shows another user QR so they can be recommended', (
    tester,
  ) async {
    const user = BangumiUser(
      id: 7,
      username: 'alice',
      nickname: 'Alice',
      avatarUrl: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFriendQr(context, user),
              child: const Text('open-qr'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-qr'));
    await tester.pumpAndSettle();

    expect(find.text('Alice 的二维码'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
    expect(find.text('把这个码给别人扫描，即可推荐添加'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });
}
