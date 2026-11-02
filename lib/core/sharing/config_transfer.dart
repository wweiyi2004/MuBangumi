import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';
import '../backup/backup_archive.dart';
import '../social/friend_groups.dart';
import '../theme/custom_colors.dart';
import '../../models/app_font.dart';

const configMaxBytes = 18 * 1024 * 1024;
const configQrPrefix = 'mubangumi-config://receive';
final configBackupCategories = BackupCategory.values
    .where((c) => !c.isDraft)
    .toSet();

class ConfigSnapshot {
  const ConfigSnapshot({
    required this.owner,
    required this.themeMode,
    required this.groups,
    this.colors,
    this.fontId,
    required this.background,
    this.backup,
  });
  final BackupOwner owner;
  final String themeMode;
  final CustomColors? colors;
  final String? fontId;
  final Map<String, dynamic> background;
  final FriendGroups groups;
  final BackupArchive? backup;
  Map<String, dynamic> toJson() => {
    'format': 'mubangumi-config',
    'version': 1,
    'owner': owner.toJson(),
    'appearance': {
      'mode': themeMode,
      'colors': colors?.toJson(),
      'font': fontId,
      'background': background,
    },
    'friends': groups.toJson(),
    if (backup != null) 'backup': jsonDecode(utf8.decode(backup!.encode())),
  };
  factory ConfigSnapshot.fromJson(Map<String, dynamic> json) {
    void only(Map map, Set<String> keys) {
      if (map.keys.any((k) => !keys.contains(k))) {
        throw const FormatException('包含不支持的配置字段');
      }
    }

    only(json, {
      'format',
      'version',
      'owner',
      'appearance',
      'friends',
      'backup',
    });
    if (json['format'] != 'mubangumi-config' || json['version'] != 1) {
      throw const FormatException('不支持的配置版本');
    }
    final owner = json['owner'], a = json['appearance'], f = json['friends'];
    if (owner is! Map<String, dynamic> ||
        a is! Map<String, dynamic> ||
        f is! Map<String, dynamic>) {
      throw const FormatException('配置内容不完整');
    }
    only(owner, {'id', 'username'});
    only(a, {'mode', 'colors', 'font', 'background'});
    if (owner['id'] is! int ||
        owner['id'] <= 0 ||
        owner['username'] is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(owner['username'])) {
      throw const FormatException('配置账号无效');
    }
    if (!['system', 'light', 'dark'].contains(a['mode'])) {
      throw const FormatException('外观模式无效');
    }
    final font = a['font'];
    if (font != null &&
        (font is! String ||
            !(downloadableFonts.any((f) => f.id == font) ||
                RegExp(r'^imported-[a-f0-9]{64}$').hasMatch(font)))) {
      throw const FormatException('字体选择无效');
    }
    final bg = a['background'];
    if (bg is! Map<String, dynamic>) throw const FormatException('背景偏好无效');
    only(bg, {'blur', 'dim', 'glass', 'reduceTransparency'});
    for (final entry in {
      'blur': (0.0, 40.0),
      'dim': (0.0, .75),
      'glass': (.15, .8),
    }.entries) {
      final value = bg[entry.key];
      if (value is! num ||
          !value.isFinite ||
          value < entry.value.$1 ||
          value > entry.value.$2) {
        throw const FormatException('背景偏好无效');
      }
    }
    if (bg['reduceTransparency'] is! bool) {
      throw const FormatException('背景偏好无效');
    }
    final backup = json['backup'] == null
        ? null
        : BackupArchive.decode(
            Uint8List.fromList(utf8.encode(jsonEncode(json['backup']))),
          );
    if (backup != null &&
        (backup.owner.id != owner['id'] ||
            backup.data.keys.any((c) => c.isDraft))) {
      throw const FormatException('本地数据账号或类别无效');
    }
    return ConfigSnapshot(
      owner: BackupOwner(owner['id'], owner['username']),
      themeMode: a['mode'],
      colors: a['colors'] == null
          ? null
          : CustomColors.fromJson(a['colors'] as Map<String, dynamic>),
      fontId: font,
      background: Map.unmodifiable(bg),
      groups: FriendGroups.fromJson(f),
      backup: backup,
    );
  }
}

List<int> _randomBytes(int count) {
  final random = Random.secure();
  return List.generate(count, (_) => random.nextInt(256));
}

String newConfigPassphrase() => base64UrlEncode(_randomBytes(18));
const _magic = [77, 85, 66, 67, 70, 71, 48, 49]; // MUBCFG01
const _headerLength = 44;
Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: 600000,
  bits: 256,
).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

/// Fixed cryptographic parameters, random salt/nonce, and authenticated expiry.
/// Call on an isolate: password stretching must not block animations or scanning.
Future<Uint8List> encryptConfig(
  (Map<String, dynamic>, String, int) input,
) async {
  final (json, password, expires) = input;
  if (password.length < 12 || password.length > 256) {
    throw const FormatException('传输口令需为 12–256 个字符');
  }
  ConfigSnapshot.fromJson(json);
  final plain = utf8.encode(jsonEncode(json));
  if (plain.length > configMaxBytes) {
    throw const FormatException('配置数据超过 18 MB');
  }
  final header = Uint8List(_headerLength)
    ..setRange(0, 8, _magic)
    ..setRange(8, 24, _randomBytes(16))
    ..setRange(24, 36, _randomBytes(12));
  ByteData.sublistView(header).setInt64(36, expires);
  final key = await _key(password, header.sublist(8, 24));
  final box = await AesGcm.with256bits().encrypt(
    plain,
    secretKey: key,
    nonce: header.sublist(24, 36),
    aad: header,
  );
  return Uint8List.fromList([...header, ...box.cipherText, ...box.mac.bytes]);
}

Future<Map<String, dynamic>> decryptConfig(
  (Uint8List, String, int) input,
) async {
  final (bytes, password, now) = input;
  if (bytes.length < _headerLength + 16 ||
      bytes.length > configMaxBytes + _headerLength + 16 ||
      password.length < 12 ||
      password.length > 256 ||
      !List.generate(8, (i) => bytes[i] == _magic[i]).every((v) => v)) {
    throw const FormatException('无效的加密配置');
  }
  final expires = ByteData.sublistView(bytes).getInt64(36);
  if (expires <= now ||
      expires > now + const Duration(days: 2).inMilliseconds) {
    throw const FormatException('传输已过期，请重新生成');
  }
  try {
    final header = bytes.sublist(0, _headerLength);
    final key = await _key(password, header.sublist(8, 24));
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(
        bytes.sublist(_headerLength, bytes.length - 16),
        nonce: header.sublist(24, 36),
        mac: Mac(bytes.sublist(bytes.length - 16)),
      ),
      secretKey: key,
      aad: header,
    );
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    ConfigSnapshot.fromJson(json);
    return json;
  } on SecretBoxAuthenticationError {
    throw const FormatException('口令不正确或数据已被修改');
  }
}

bool configPrivateIpv4(String host) {
  final ip = InternetAddress.tryParse(host);
  if (ip == null || ip.type != InternetAddressType.IPv4 || ip.address != host) {
    return false;
  }
  final b = ip.rawAddress;
  return b[0] == 10 ||
      b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
      b[0] == 192 && b[1] == 168;
}

class ConfigInvitation {
  const ConfigInvitation({
    required this.host,
    required this.port,
    required this.id,
    required this.hash,
    required this.expires,
  });
  final String host, id, hash;
  final int port, expires;
  String get qr => Uri(
    scheme: 'mubangumi-config',
    host: 'receive',
    queryParameters: {
      'v': '1',
      'host': host,
      'port': '$port',
      'id': id,
      'hash': hash,
      'expires': '$expires',
    },
  ).toString();
  factory ConfigInvitation.parse(String raw, {DateTime? now}) {
    final uri = Uri.parse(raw);
    final q = uri.queryParameters;
    final port = int.tryParse(q['port'] ?? '') ?? 0,
        expiry = int.tryParse(q['expires'] ?? '') ?? 0;
    final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
    if (uri.scheme != 'mubangumi-config' ||
        uri.host != 'receive' ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.hasPort ||
        q.length != 6 ||
        uri.queryParametersAll.values.any((v) => v.length != 1) ||
        q['v'] != '1' ||
        !configPrivateIpv4(q['host'] ?? '') ||
        port < 1024 ||
        port > 65535 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(q['id'] ?? '') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(q['hash'] ?? '') ||
        expiry <= time ||
        expiry > time + const Duration(minutes: 11).inMilliseconds) {
      throw const FormatException('无效或过期的配置二维码');
    }
    return ConfigInvitation(
      host: q['host']!,
      port: port,
      id: q['id']!,
      hash: q['hash']!,
      expires: expiry,
    );
  }
  Uri get endpoint => Uri(scheme: 'http', host: host, port: port, path: '/$id');
}

class ConfigTransferServer {
  ConfigTransferServer._(this._server, this.invitation, this._timer);
  final HttpServer _server;
  final ConfigInvitation invitation;
  final Timer _timer;
  bool _closed = false;
  final _completion = Completer<void>();
  Future<void> get closed => _completion.future;
  static Future<List<String>> addresses() async => [
    for (final network in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    ))
      for (final ip in network.addresses)
        if (configPrivateIpv4(ip.address)) ip.address,
  ];
  static Future<ConfigTransferServer> start(
    String host,
    Uint8List encrypted,
  ) async {
    if (!configPrivateIpv4(host) || encrypted.length > configMaxBytes + 60) {
      throw const FormatException('请选择当前设备的局域网地址');
    }
    final server = await HttpServer.bind(InternetAddress(host), 0);
    final invite = ConfigInvitation(
      host: host,
      port: server.port,
      id: _randomBytes(
        32,
      ).map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
      hash: digest.sha256.convert(encrypted).toString(),
      expires: DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
    );
    late final ConfigTransferServer result;
    final timer = Timer(const Duration(minutes: 10), () => result.close());
    result = ConfigTransferServer._(server, invite, timer);
    server.listen((request) async {
      try {
        if (request.method != 'GET' ||
            request.uri.path != '/${invite.id}' ||
            request.uri.hasQuery ||
            DateTime.now().millisecondsSinceEpoch >= invite.expires) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.contentType = ContentType.binary;
          request.response.headers.set(
            HttpHeaders.cacheControlHeader,
            'no-store',
          );
          request.response.contentLength = encrypted.length;
          request.response.add(encrypted);
        }
        await request.response.close();
      } catch (_) {
        request.response.detachSocket().then(
          (s) => s.destroy(),
          onError: (Object _) {},
        );
      }
    });
    return result;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer.cancel();
    await _server.close(force: true);
    if (!_completion.isCompleted) _completion.complete();
  }
}

Future<Uint8List> receiveConfig(
  ConfigInvitation invitation, {
  HttpClient Function()? clientFactory,
}) async {
  // Validate again at the actual network boundary; do not follow redirects.
  final invite = ConfigInvitation.parse(invitation.qr);
  final client = (clientFactory ?? HttpClient.new)()
    ..connectionTimeout = const Duration(seconds: 10);
  final deadline = Timer(
    const Duration(minutes: 1),
    () => client.close(force: true),
  );
  try {
    final request = await client.getUrl(invite.endpoint);
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > configMaxBytes + 60) {
      throw const FormatException('无法读取源设备，请检查同一 Wi-Fi 和防火墙');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > configMaxBytes + 60) {
        throw const FormatException('传输内容过大');
      }
      bytes.add(chunk);
    }
    final result = bytes.takeBytes();
    if (DateTime.now().millisecondsSinceEpoch >= invite.expires ||
        digest.sha256.convert(result).toString() != invite.hash) {
      throw const FormatException('传输过期或数据校验失败');
    }
    return result;
  } finally {
    deadline.cancel();
    client.close(force: true);
  }
}
