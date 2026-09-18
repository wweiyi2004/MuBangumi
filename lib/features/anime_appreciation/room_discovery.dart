import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';

class LocatedRoom {
  const LocatedRoom(this.invite, this.preview);
  final RoomInvite invite;
  final Json preview;
}

typedef RoomProbe =
    Future<Json> Function(Uri origin, String endpoint, Json body);

/// Bounded parallel attempts to addresses carried by the QR. This never scans
/// arbitrary subnets and never sends account or participant credentials.
class RoomDiscovery {
  RoomDiscovery({this.probe, this.timeout = const Duration(seconds: 4)});
  final RoomProbe? probe;
  final Duration timeout;
  final _clients = <HttpClient>{};
  bool _closed = false;
  void close() {
    _closed = true;
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }

  Future<Json> _request(Uri origin, String endpoint, Json data) async {
    if (_closed) throw const RoomError(499, '已取消寻找');
    if (probe != null) return probe!(origin, endpoint, data);
    final client = HttpClient()..connectionTimeout = timeout;
    _clients.add(client);
    try {
      final request = await client.postUrl(origin.resolve('/api/$endpoint'));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(data));
      final response = await request.close();
      var content = '';
      await for (final chunk in response.transform(utf8.decoder)) {
        content += chunk;
        if (content.length > 8192) throw const RoomError(502, '探测响应无效');
      }
      if (response.statusCode != 200) {
        throw RoomError(response.statusCode, '该地址无法进入这场活动');
      }
      final decoded = jsonDecode(content);
      if (decoded is! Json) throw const RoomError(502, '探测响应无效');
      return decoded;
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Future<LocatedRoom> find(RoomInvite target) async {
    final done = Completer<LocatedRoom>();
    var remaining = target.candidates.length;
    for (final origin in target.candidates) {
      unawaited(() async {
        try {
          final nonce = newSecret();
          final proof = await _request(origin, 'locate', {
            'event': target.eventId,
            'nonce': nonce,
          });
          if (_closed ||
              proof['service'] != 'mubangumi-banjian' ||
              proof['protocol'] != 1 ||
              proof['event'] != target.eventId ||
              proof['proof'] !=
                  roomLocationProof(target.secret, target.eventId, nonce)) {
            throw const RoomError(403, '该地址不是邀请中的活动');
          }
          final preview = await _request(origin, 'preview', {
            'event': target.eventId,
            'invite': target.secret,
          });
          if (preview['id'] != target.eventId ||
              preview['title'] is! String ||
              preview['ended'] is! bool) {
            throw const RoomError(502, '活动信息不完整');
          }
          if (!done.isCompleted) {
            done.complete(LocatedRoom(target.at(origin), preview));
          }
        } catch (_) {
          remaining--;
          if (remaining == 0 && !done.isCompleted) {
            done.completeError(
              const RoomError(
                503,
                '没有找到可连接的番键会。请连接主持人的同一 Wi-Fi / 热点后重试；也可让主持人重新分享二维码或使用在线服务器入口。',
              ),
            );
          }
        }
      }());
    }
    try {
      return await done.future.timeout(
        timeout,
        onTimeout: () => throw const RoomError(
          503,
          '暂时找不到这场活动。请确认已连接同一 Wi-Fi / 热点，主持人的服务仍在运行，再重试。',
        ),
      );
    } finally {
      close();
    }
  }
}
