import 'dart:async';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/anime_appreciation/room_discovery.dart';

const event = 'abcdefghijklmnopqrstuv';
const secret = 'abcdefghijklmnopqrstuvwxyz123456';
RoomInvite invitation() => RoomInvite(
  Uri.parse('http://192.168.1.10:43928'),
  event,
  secret,
  alternates: [
    Uri.parse('http://192.168.137.1:43928'),
    Uri.parse('http://10.1.2.3:43928'),
  ],
);
Json proof(Json body) => {
  'service': 'mubangumi-banjian',
  'protocol': 1,
  'event': event,
  'proof': roomLocationProof(secret, event, body['nonce']),
};
Json preview() => {'id': event, 'title': '今晚的番键会', 'ended': false, 'count': 3};
void main() {
  test(
    'one ordinary browser URL retains bounded native alternatives and old links',
    () {
      final link = invitation();
      final parsed = RoomInvite.parse(link.url)!;
      expect(Uri.parse(link.url).scheme, 'http');
      expect(Uri.parse(link.url).path, '/join/$event');
      expect(
        parsed.candidates.map((v) => v.origin),
        link.candidates.map((v) => v.origin),
      );
      expect(parsed.secret, secret);
      expect(parsed.sameRoom(link.at(link.alternates.first)), true);
      final old = RoomInvite.parse(
        'http://192.168.1.10:43928/join/$event#invite=$secret',
      );
      expect(old!.candidates.length, 1);
    },
  );
  test(
    'untrusted alternatives cannot target public IPs, credentials, loopback or other ports',
    () {
      final parsed = RoomInvite.parse(
        '${invitation().base}/join/$event#invite=$secret&hosts=8.8.8.8,127.0.0.1,169.254.169.254,192.168.1.2,evil.test',
      );
      expect(parsed!.candidates.map((v) => v.host), [
        '192.168.1.10',
        '192.168.1.2',
      ]);
      final cloud = RoomInvite.parse(
        'https://example.com/join/$event#invite=$secret&hosts=192.168.1.2',
      );
      expect(cloud!.candidates.length, 1);
      final bad = RoomInvite(
        invitation().base,
        event,
        secret,
        alternates: [
          Uri.parse('http://192.168.1.2:22'),
          Uri.parse('http://user:pass@192.168.1.3:43928'),
        ],
      );
      expect(bad.candidates.length, 1);
    },
  );
  test(
    'too many candidate hosts and malformed fragments are rejected safely',
    () {
      final hosts = List.generate(9, (i) => '192.168.1.${i + 1}').join(',');
      expect(
        RoomInvite.parse('${invitation().url}&hosts=$hosts')!.candidates.length,
        1,
      );
      expect(
        RoomInvite.parse('${invitation().base}/join/$event#invite=%'),
        null,
      );
    },
  );
  test(
    'ranking puts hotspot and Wi-Fi ahead of VM adapters and link-local addresses',
    () {
      final ranked = rankRoomAddresses([
        RoomShareAddress(
          'VMware Network Adapter VMnet8',
          Uri.parse('http://192.168.68.1:43928'),
        ),
        RoomShareAddress('WLAN', Uri.parse('http://10.128.138.186:43928')),
        RoomShareAddress('以太网 2', Uri.parse('http://169.254.34.193:43928')),
        RoomShareAddress('ap0', Uri.parse('http://192.168.43.1:43928')),
        RoomShareAddress('Tailscale', Uri.parse('http://100.64.18.19:43928')),
      ]);
      expect(ranked.take(2).map((v) => v.interfaceName), ['ap0', 'WLAN']);
      expect(ranked[2].virtual, true);
      expect(ranked[2].kind, '虚拟网络');
    },
  );
  test(
    'parallel discovery succeeds even when preferred address hangs',
    () async {
      final calls = <String>[];
      final found = await RoomDiscovery(
        timeout: const Duration(milliseconds: 300),
        probe: (base, path, body) async {
          calls.add('${base.host}/$path');
          if (base.host == '192.168.1.10') return Completer<Json>().future;
          if (base.host == '10.1.2.3') {
            throw const RoomError(404, 'another service');
          }
          return path == 'locate' ? proof(body) : preview();
        },
      ).find(invitation());
      expect(found.invite.base.host, '192.168.137.1');
      expect(found.preview['title'], '今晚的番键会');
      expect(calls, contains('192.168.1.10/locate'));
      expect(calls, contains('192.168.137.1/preview'));
    },
  );
  test(
    'wrong service never receives invite secret or participant credentials',
    () async {
      final sent = <Json>[];
      final found = await RoomDiscovery(
        probe: (base, path, body) async {
          if (base.host != '192.168.137.1') {
            sent.add(body);
            expect(path, 'locate');
            return {
              'service': 'mubangumi-banjian',
              'protocol': 1,
              'event': event,
              'proof': 'forged',
            };
          }
          return path == 'locate' ? proof(body) : preview();
        },
      ).find(invitation());
      expect(found.invite.base.host, '192.168.137.1');
      expect(sent, isNotEmpty);
      for (final body in sent) {
        expect(body.containsKey('invite'), false);
        expect(body.containsKey('token'), false);
      }
    },
  );
  test(
    'correctly signed response for a different event is not accepted',
    () async {
      await expectLater(
        RoomDiscovery(
          probe: (base, path, body) async => {...proof(body), 'event': 'wrong'},
        ).find(invitation()),
        throwsA(isA<RoomError>()),
      );
    },
  );
  test(
    'all failed candidates provide a Wi-Fi / hotspot retry explanation',
    () async {
      await expectLater(
        RoomDiscovery(
          probe: (base, path, body) async =>
              throw const RoomError(404, 'absent'),
        ).find(invitation()),
        throwsA(
          isA<RoomError>().having(
            (e) => e.message,
            'message',
            contains('Wi-Fi'),
          ),
        ),
      );
    },
  );
  test(
    'all hung candidates finish within the single discovery deadline',
    () async {
      final timer = Stopwatch()..start();
      await expectLater(
        RoomDiscovery(
          timeout: const Duration(milliseconds: 50),
          probe: (base, path, body) => Completer<Json>().future,
        ).find(invitation()),
        throwsA(isA<RoomError>()),
      );
      expect(timer.elapsedMilliseconds, lessThan(1000));
    },
  );
}
