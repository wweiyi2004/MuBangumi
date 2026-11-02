import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/sharing/config_transfer.dart';
import 'package:mubangumi/core/social/friend_groups.dart';

ConfigSnapshot fixture() => ConfigSnapshot(
  owner: const BackupOwner(1, 'alice'),
  themeMode: 'system',
  groups: FriendGroups().rename(null, '一起追番'),
  background: const {
    'blur': 22.0,
    'dim': .32,
    'glass': .42,
    'reduceTransparency': false,
  },
  backup: BackupArchive.create(
    owner: const BackupOwner(1, 'alice'),
    data: {
      BackupCategory.pins: [
        {'subject_id': 42, 'position': 0},
      ],
    },
  ),
);

void main() {
  test(
    'configuration rejects credentials, foreign owners, drafts and unsafe preferences',
    () {
      final json = fixture().toJson();
      expect(ConfigSnapshot.fromJson(json).backup!.owner.id, 1);
      expect(
        () => ConfigSnapshot.fromJson({...json, 'access_token': 'synthetic'}),
        throwsFormatException,
      );
      final a = Map<String, dynamic>.from(json['appearance']);
      expect(
        () => ConfigSnapshot.fromJson({
          ...json,
          'appearance': {...a, 'font': '../../token'},
        }),
        throwsFormatException,
      );
      expect(
        () => ConfigSnapshot.fromJson({
          ...json,
          'appearance': {
            ...a,
            'background': {...a['background'] as Map, 'imagePath': 'private'},
          },
        }),
        throwsFormatException,
      );
      final other = BackupArchive.create(
        owner: const BackupOwner(2, 'bob'),
        data: {BackupCategory.pins: []},
      );
      final draft = BackupArchive.create(
        owner: const BackupOwner(1, 'alice'),
        data: {BackupCategory.communityDrafts: []},
      );
      for (final archive in [other, draft]) {
        expect(
          () => ConfigSnapshot.fromJson({
            ...json,
            'backup': ConfigSnapshot(
              owner: archive.owner,
              themeMode: 'system',
              groups: FriendGroups(),
              background: fixture().background,
              backup: archive,
            ).toJson()['backup'],
          }),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'AES-GCM round trip rejects tampering, wrong passwords, expiry and short passwords',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final pass = newConfigPassphrase();
      final encrypted = await encryptConfig((
        fixture().toJson(),
        pass,
        now + 600000,
      ));
      expect(String.fromCharCodes(encrypted), isNot(contains('alice')));
      final opened = ConfigSnapshot.fromJson(
        await decryptConfig((encrypted, pass, now)),
      );
      expect(opened.owner.username, 'alice');
      expect(
        opened.backup!.data[BackupCategory.pins]!.single['subject_id'],
        42,
      );
      expect(opened.groups.names.values.single, '一起追番');
      final altered = Uint8List.fromList(encrypted);
      altered[50] ^= 1;
      await expectLater(
        decryptConfig((altered, pass, now)),
        throwsFormatException,
      );
      await expectLater(
        decryptConfig((encrypted, 'wrong-password', now)),
        throwsFormatException,
      );
      await expectLater(
        decryptConfig((encrypted, pass, now + 600001)),
        throwsFormatException,
      );
      await expectLater(
        encryptConfig((fixture().toJson(), '123456', now + 600000)),
        throwsFormatException,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'new encryptions use independent salts and nonces',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch,
          pass = newConfigPassphrase();
      final a = await encryptConfig((fixture().toJson(), pass, now + 600000));
      final b = await encryptConfig((fixture().toJson(), pass, now + 600000));
      expect(a.sublist(8, 36), isNot(b.sublist(8, 36)));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'QR invitation never contains the key and restricts hosts, redirects and expiration',
    () {
      final invite = invitation([1, 2, 3]);
      expect(ConfigInvitation.parse(invite.qr).endpoint.host, '192.168.1.3');
      for (final host in [
        '127.0.0.1',
        '169.254.169.254',
        '8.8.8.8',
        'example.com',
        '::1',
        '192.168.1.3.evil.com',
      ]) {
        expect(
          () => ConfigInvitation.parse(
            invite.qr.replaceFirst('192.168.1.3', host),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => ConfigInvitation.parse('${invite.qr}&host=192.168.1.4'),
        throwsFormatException,
      );
      expect(
        () => ConfigInvitation.parse(
          invite.qr,
          now: DateTime.fromMillisecondsSinceEpoch(invite.expires + 1),
        ),
        throwsFormatException,
      );
      expect(invite.qr, isNot(contains('password')));
      expect(invite.qr, isNot(contains('alice')));
    },
  );
  test(
    'receiver enforces bounded encrypted bytes and closes clients',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final client = FakeClient(FakeResponse(bytes));
      final got = await receiveConfig(
        invitation(bytes),
        clientFactory: () => client,
      );
      expect(got, bytes);
      expect(client.request.followRedirects, false);
      expect(client.closed, true);
      expect(client.uri!.path, '/${invitation(bytes).id}');
      for (final response in [
        FakeResponse(bytes, status: 302),
        FakeResponse(bytes, size: configMaxBytes + 61),
        FakeResponse([3, 2, 1]),
      ]) {
        final bad = FakeClient(response);
        await expectLater(
          receiveConfig(invitation(bytes), clientFactory: () => bad),
          throwsFormatException,
        );
        expect(bad.closed, true);
      }
    },
  );
}

ConfigInvitation invitation(List<int> bytes) => ConfigInvitation(
  host: '192.168.1.3',
  port: 34567,
  id: List.filled(64, 'a').join(),
  hash: sha256.convert(bytes).toString(),
  expires: DateTime.now()
      .add(const Duration(minutes: 10))
      .millisecondsSinceEpoch,
);

class FakeClient implements HttpClient {
  @override
  Duration? connectionTimeout;
  FakeClient(this.response);
  final FakeResponse response;
  bool closed = false;
  Uri? uri;
  final request = FakeRequest();
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    uri = url;
    request.response = response;
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRequest implements HttpClientRequest {
  late FakeResponse response;
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  FakeResponse(this.bytes, {int status = 200, int? size})
    : statusCode = status,
      contentLength = size ?? bytes.length;
  final List<int> bytes;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
