import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

typedef Json = Map<String, dynamic>;
Uri? roomCoverUri(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      raw.length > 2048 ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !['http', 'https'].contains(uri.scheme) ||
      !['lain.bgm.tv', 'lain.bangumi.tv'].contains(uri.host) ||
      (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) ||
      !uri.path.contains('/pic/cover/'))
    return null;
  return uri.replace(scheme: 'https', port: 443);
}

String newSecret([int bytes = 24]) => base64UrlEncode(
  List.generate(bytes, (_) => Random.secure().nextInt(256)),
).replaceAll('=', '');
String digest(String value) => sha256.convert(utf8.encode(value)).toString();
String roomLocationProof(String secret, String event, String nonce) => Hmac(
  sha256,
  utf8.encode(secret),
).convert(utf8.encode('banjian-locate-v1:$event:$nonce')).toString();
Json clone(Json value) => jsonDecode(jsonEncode(value)) as Json;

class RoomError implements Exception {
  const RoomError(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

Never reject(String message, [int status = 400]) =>
    throw RoomError(status, message);
String textField(Json data, String key, {int max = 500, bool empty = false}) {
  final value = data[key];
  if (value is! String ||
      (!empty && value.trim().isEmpty) ||
      value.runes.length > max) {
    reject('$key 内容无效或过长');
  }
  return value.trim();
}

int intField(Json data, String key, {int min = 0, int max = 0x7fffffff}) {
  final value = data[key];
  if (value is! int || value < min || value > max) reject('$key 数值无效');
  return value;
}

/// No account credentials travel with an invitation. HTTP is limited to LAN.
class RoomInvite {
  const RoomInvite(
    this.base,
    this.eventId,
    this.secret, {
    this.alternates = const [],
  });
  final Uri base;
  final String eventId;
  final String secret;
  final List<Uri> alternates;
  String get identityKey => digest('banjian:$eventId:$secret');
  bool sameRoom(RoomInvite? other) =>
      other?.eventId == eventId && other?.secret == secret;
  List<Uri> get candidates =>
      [
        base,
        if (base.scheme == 'http')
          ...alternates.where(
            (uri) =>
                isPrivateLanHost(uri.host) &&
                uri.scheme == 'http' &&
                uri.port == base.port &&
                uri.userInfo.isEmpty &&
                !uri.hasQuery &&
                !uri.hasFragment &&
                (uri.path.isEmpty || uri.path == '/') &&
                uri.origin != base.origin,
          ),
      ].fold<List<Uri>>([], (out, uri) {
        if (out.length < 8 && !out.any((value) => value.origin == uri.origin))
          out.add(uri);
        return out;
      });
  RoomInvite at(Uri address) => RoomInvite(
    address,
    eventId,
    secret,
    alternates: candidates
        .where((uri) => uri.origin != address.origin)
        .toList(),
  );
  String get url => base
      .resolve('/join/$eventId')
      .replace(
        fragment:
            'invite=$secret${candidates.length > 1 ? '&hosts=${candidates.skip(1).map((uri) => uri.host).join(',')}' : ''}',
      )
      .toString();
  static RoomInvite? parse(String raw) {
    try {
      if (raw.length > 2048) return null;
      final uri = Uri.tryParse(raw.trim());
      if (uri == null ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          !validServerUri(uri) ||
          uri.pathSegments.length != 2 ||
          uri.pathSegments.first != 'join')
        return null;
      final id = uri.pathSegments.last;
      final values = Uri.splitQueryString(uri.fragment);
      final secret = values['invite'] ?? '';
      if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(id) ||
          !RegExp(r'^[A-Za-z0-9_-]{24,128}$').hasMatch(secret))
        return null;
      return RoomInvite(
        uri.replace(path: '/', fragment: '', query: null),
        id,
        secret,
        alternates: baseAlternates(uri, values['hosts']),
      );
    } on FormatException {
      return null;
    }
  }
}

List<Uri> baseAlternates(Uri base, String? raw) {
  if (base.scheme != 'http' || raw == null || raw.length > 128) return const [];
  final hosts = raw.split(',');
  if (hosts.length > 7) return const [];
  return [
    for (final host in hosts)
      if (isPrivateLanHost(host))
        Uri(scheme: 'http', host: host, port: base.port),
  ];
}

bool isPrivateLanHost(String host) {
  if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return false;
  final p = host.split('.').map(int.parse).toList();
  if (p.any((n) => n > 255)) return false;
  return p[0] == 10 ||
      (p[0] == 192 && p[1] == 168) ||
      (p[0] == 172 && p[1] >= 16 && p[1] <= 31);
}

bool validServerUri(Uri uri) {
  if (uri.userInfo.isNotEmpty || uri.host.isEmpty) return false;
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  final h = uri.host;
  if (h == 'localhost' || h == '::1') return true;
  final p = h.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.any((v) => v == null || v < 0 || v > 255))
    return false;
  return p[0] == 127 ||
      p[0] == 10 ||
      (p[0] == 192 && p[1] == 168) ||
      (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) ||
      (p[0] == 169 && p[1] == 254);
}
