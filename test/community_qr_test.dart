import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zxing2/qrcode.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/social/community_qr.dart';
import 'package:mubangumi/core/social/friend_qr.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/widgets/friend_qr_actions.dart';
import 'package:mubangumi/widgets/group_qr_sheet.dart';
import 'package:mubangumi/screens/community_group_screen.dart';

void main() {
  testWidgets('account change invalidates a private group detail response', (
    tester,
  ) async {
    final service = _AccountGroups()..setCurrentUsername('alice');
    await tester.pumpWidget(
      AppRouteScope(
        resolve: AppRouter.resolve,
        child: MaterialApp(
          home: CommunityGroupScreen(
            group: _Service.group,
            service: service,
            initialDetail: const CommunityGroupDetail(
              group: CommunityGroup(
                name: '旧账号小组',
                url: 'https://bgm.tv/group/boring',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    service.setCurrentUsername('bob');
    await tester.pumpAndSettle();
    service.pending.complete(
      const CommunityGroupDetail(
        group: CommunityGroup(
          name: '旧账号小组',
          url: 'https://bgm.tv/group/boring',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('旧账号小组'), findsNothing);
    expect(find.text('当前账号小组'), findsWidgets);
  });
  test('official group URLs and old friend payloads remain distinct', () {
    for (final host in ['bgm.tv', 'bangumi.tv', 'chii.in']) {
      final target = CommunityQr.decode('https://$host/group/boring');
      expect(target?.kind, CommunityQrKind.group);
      expect(target?.identifier, 'boring');
    }
    expect(CommunityQr.groupUrl('boring'), 'https://bgm.tv/group/boring');
    expect(
      CommunityQr.decode(FriendQr.encode('alice'))?.kind,
      CommunityQrKind.friend,
    );
    expect(
      CommunityQr.decode('https://bgm.tv/user/alice')?.kind,
      CommunityQrKind.friend,
    );
  });
  test(
    'QR parser rejects foreign hosts, actions, encoded separators and malformed payloads',
    () {
      for (final value in [
        'https://bgm.tv.evil.example/group/boring',
        'https://bgm.tv@evil.example/group/boring',
        'https://bgm.tv:444/group/boring',
        'javascript:alert(1)',
        'https://bgm.tv/group/boring/join',
        'https://bgm.tv/group/topic/123',
        'https://bgm.tv/group/a%2Fb',
        'https://bgm.tv/group/..',
        'mubangumi:friend:v1:a%0Ab',
      ]) {
        expect(CommunityQr.decode(value), isNull, reason: value);
      }
    },
  );
  test('group QR images decode through the shared image reader', () {
    final payload = CommunityQr.groupUrl('boring');
    final matrix = Encoder.encode(payload, ErrorCorrectionLevel.m).matrix!;
    const scale = 8;
    final image = img.Image(
      width: matrix.width * scale,
      height: matrix.height * scale,
    );
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    for (var x = 0; x < matrix.width; x++) {
      for (var y = 0; y < matrix.height; y++) {
        if (matrix.get(x, y) == 1) {
          img.fillRect(
            image,
            x1: x * scale,
            y1: y * scale,
            x2: x * scale + scale - 1,
            y2: y * scale + scale - 1,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }
    final bytes = Uint8List.fromList(img.encodePng(image));
    final decoded = FriendQr.decodePayloadFromImageBytes(bytes);
    expect(CommunityQr.decode(decoded!)?.identifier, 'boring');
    expect(FriendQr.decodeFromImageBytes(bytes), isNull);
  });
  testWidgets(
    'scanning a group only opens its details, without joining or adding a friend',
    (tester) async {
      final service = _Service();
      await tester.pumpWidget(
        AppRouteScope(
          resolve: AppRouter.resolve,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => scanAndAddFriend(
                    context,
                    myUsername: 'alice',
                    service: service,
                    reader: (_) async => 'https://bgm.tv/group/boring',
                  ),
                  child: const Text('扫一扫'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('扫一扫'));
      await tester.pumpAndSettle();
      expect(find.text('测试小组'), findsWidgets);
      expect(find.text('加入'), findsOneWidget);
      expect(service.previews, 1);
      expect(service.friendWrites, 0);
      expect(find.text('发起讨论'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'group QR sheet explains confirmation and provides a visible QR',
    (tester) async {
      await tester.pumpWidget(
        AppRouteScope(
          resolve: AppRouter.resolve,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showGroupQr(context, _Service.group),
                  child: const Text('分享小组'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('分享小组'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('扫码查看小组，再选择是否加入'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Service extends CommunityService {
  _Service() : super.test();
  static const group = CommunityGroup(
    id: 1,
    slug: 'boring',
    name: '测试小组',
    url: 'https://bgm.tv/group/boring',
  );
  int previews = 0, friendWrites = 0;
  @override
  Future<CommunityGroupDetail> loadGroupPreview(String slug) async {
    previews++;
    return const CommunityGroupDetail(group: group, accessible: false);
  }

  @override
  Future<CommunityGroupDetail?> readCachedGroupDetail(String slug) async =>
      null;
  @override
  Future<CommunityGroupDetail> loadGroupDetail(
    String slug, {
    bool refresh = false,
  }) async => const CommunityGroupDetail(group: group, accessible: false);
  @override
  Future<void> addFriend(String username) async {
    friendWrites++;
  }
}

class _AccountGroups extends CommunityService {
  _AccountGroups() : super.test();
  final pending = Completer<CommunityGroupDetail>();
  @override
  Future<CommunityGroupDetail?> readCachedGroupDetail(String slug) async =>
      null;
  @override
  Future<CommunityGroupDetail> loadGroupDetail(
    String slug, {
    bool refresh = false,
  }) async => currentUsername == 'alice'
      ? await pending.future
      : const CommunityGroupDetail(
          group: CommunityGroup(
            name: '当前账号小组',
            slug: 'boring',
            url: 'https://bgm.tv/group/boring',
          ),
        );
}
