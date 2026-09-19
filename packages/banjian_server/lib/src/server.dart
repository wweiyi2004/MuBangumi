import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:qr/qr.dart';
import 'protocol.dart';
import 'room_models.dart';
import 'store.dart';
import 'share_address.dart';
import 'cover_cache.dart';

class RoomServer {
  RoomServer({
    required this.store,
    required String adminPassword,
    required this.assets,
    this.publicOrigin,
    this.autoCacheCovers = true,
    RoomCoverLoader? coverLoader,
    Future<String?> Function(int)? coverLookup,
    Future<WebSocket> Function(HttpRequest)? upgradeWebSocket,
  }) : _passwordHash = digest(adminPassword),
       _upgradeWebSocket = upgradeWebSocket ?? WebSocketTransformer.upgrade {
    if (adminPassword.length < 12) throw ArgumentError('管理密码至少 12 位');
    coverCache = RoomCoverCache(
      store,
      loader: coverLoader,
      lookup:
          coverLookup ??
          (id) async {
            final raw = await _bangumi('subjects/$id') as Json;
            return raw['images']?['common'] as String? ??
                raw['images']?['large'] as String?;
          },
    );
  }
  final bool autoCacheCovers;
  final Future<WebSocket> Function(HttpRequest) _upgradeWebSocket;
  late final RoomCoverCache coverCache;
  final _coverJobs = <String, Future<void>>{};
  Timer? _coverRetry;
  final RoomStore store;
  final Map<String, List<int>> assets;
  final String? publicOrigin;
  final String _passwordHash;
  final String _serverEpoch = newSecret(12);
  final _sessions = <String, DateTime>{};
  final _rates = <String, List<DateTime>>{};
  final _sockets =
      <
        WebSocket,
        ({String event, String token, bool admin, bool invalidate})
      >{};
  Timer? _broadcastTimer;
  final _allSockets = <WebSocket>{};
  final _socketVersions = <WebSocket, int>{};
  HttpServer? _server;
  bool _closed = false;
  int get port => _server!.port;
  Future<void> start({int port = 43928, InternetAddress? address}) async {
    _server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.idleTimeout = const Duration(seconds: 20);
    _server!.listen((r) {
      unawaited(_handle(r));
    });
    if (autoCacheCovers) {
      void retry() {
        if (!_closed) {
          for (final e in store.history().where((e) => e['ended'] != true)) {
            unawaited(repairCovers(e['id']));
          }
        }
      }

      retry();
      _coverRetry = Timer.periodic(const Duration(minutes: 2), (_) => retry());
    }
  }

  Future<void> repairCovers(String id) {
    final existing = _coverJobs[id];
    if (existing != null) return existing;
    final job = _repairCovers(id).catchError((Object _) {}).whenComplete(() {
      _coverJobs.remove(id);
    });
    _coverJobs[id] = job;
    return job;
  }

  Future<void> _repairCovers(String id) async {
    final attempted = <String>{};
    while (!_closed) {
      final e = store.info(id);
      final next = (e['rounds'] as List)
          .cast<Json>()
          .where(
            (r) =>
                !attempted.contains(r['id']) &&
                !coverCache.contains(r['subject']['cover'] as String? ?? ''),
          )
          .firstOrNull;
      if (next == null) return;
      final rid = next['id'] as String;
      attempted.add(rid);
      final subject = next['subject'] as Json;
      try {
        final cover = await coverCache.ensure(subject);
        if (_closed) return;
        if (store.updateRoundCover(id, rid, subject['id'], cover: cover))
          _broadcast();
      } catch (_) {
        if (_closed) return;
        if (store.updateRoundCover(
          id,
          rid,
          subject['id'],
          error: '封面暂未缓存，请在服务设备联网后重试',
        ))
          _broadcast();
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    coverCache.closed = true;
    _coverRetry?.cancel();
    _broadcastTimer?.cancel();
    for (final ws in _allSockets.toList()) {
      unawaited(ws.close(1001, '服务已停止'));
    }
    await _server?.close(force: true);
  }

  Future<RoomInvite> invitation(HttpRequest r) async {
    var e = store.info(r.uri.queryParameters['event'] ?? '');
    if (e['ended'] == true)
      reject('这场活动已结束，不能再邀请新参与者。请打开正在进行的活动并重新分享二维码。', 409);
    if (publicOrigin != null)
      return RoomInvite(Uri.parse(publicOrigin!), e['id'], e['invite']);
    final requestBase = Uri.parse('http://${r.headers.value('host')}');
    if (_server!.address.isLoopback)
      return RoomInvite(requestBase, e['id'], e['invite']);
    final choices = (await listRoomAddresses(
      port,
    )).where((v) => v.privateLan).toList();
    e = store.info(e['id']);
    if (e['ended'] == true) reject('这场活动已结束，请重新获取正在进行的活动二维码。', 409);
    // A remote browser already reached this address: retain its working route.
    final primary = choices.any((v) => v.uri.origin == requestBase.origin)
        ? requestBase
        : choices.firstOrNull?.uri ?? requestBase;
    return RoomInvite(
      primary,
      e['id'],
      e['invite'],
      alternates: choices.map((v) => v.uri).toList(),
    );
  }

  String _qrSvg(String url) {
    final code = QrImage(
      QrCode.fromData(data: url, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    final size = code.moduleCount + 8;
    final svg = StringBuffer(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size"><rect width="$size" height="$size" fill="white"/><g fill="black">',
    );
    for (var y = 0; y < code.moduleCount; y++) {
      for (var x = 0; x < code.moduleCount; x++) {
        if (code.isDark(y, x))
          svg.write('<rect x="${x + 4}" y="${y + 4}" width="1" height="1"/>');
      }
    }
    return '${svg.toString()}</g></svg>';
  }

  String _bearer(HttpRequest r) {
    final auth = r.headers.value('authorization') ?? '';
    return auth.startsWith('Bearer ') ? auth.substring(7) : '';
  }

  bool _admin(String token) {
    final expiry = _sessions[digest(token)];
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  void _requireAdmin(String token) {
    if (!_admin(token)) reject('管理登录已失效，请重新登录', 401);
  }

  bool _originAllowed(HttpRequest r, String? origin) {
    if (origin == null)
      return true; // Native clients send explicit bearer auth.
    return origin == publicOrigin ||
        origin == 'http://${r.headers.value('host')}';
  }

  void _rate(String key, int limit, int seconds) {
    final now = DateTime.now();
    if (_rates.length > 2000) {
      _rates.removeWhere(
        (_, v) => v.isEmpty || now.difference(v.last).inMinutes > 10,
      );
      if (_rates.length > 2000) reject('服务繁忙，请稍后重试', 429);
    }
    final times = _rates.putIfAbsent(key, () => []);
    times.removeWhere((t) => now.difference(t).inSeconds >= seconds);
    if (times.length >= limit) reject('操作频繁，请稍后重试', 429);
    times.add(now);
  }

  Future<Json> _body(HttpRequest r) async {
    if (r.headers.contentType?.mimeType != 'application/json')
      reject('需要 JSON 请求', 415);
    if (r.contentLength > 32768) reject('请求过大', 413);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in r.timeout(const Duration(seconds: 10))) {
      builder.add(chunk);
      if (builder.length > 32768) reject('请求过大', 413);
    }
    final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
    if (decoded is! Json) reject('请求格式无效');
    return decoded;
  }

  void _json(HttpResponse response, Object value, [int status = 200]) {
    final bytes = utf8.encode(jsonEncode(value));
    if (bytes.length > RoomLimits.snapshotBytes)
      throw const RoomError(413, '活动响应超过快照上限，请使用分页或导出');
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.add(bytes);
  }

  Future<void> _handle(HttpRequest r) async {
    var upgraded = false;
    try {
      r.response.headers.set('Cache-Control', 'no-store');
      r.response.headers.set('X-Content-Type-Options', 'nosniff');
      r.response.headers.set('Referrer-Policy', 'no-referrer');
      r.response.headers.set(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
      );
      if (!_originAllowed(r, r.headers.value('origin'))) reject('不允许跨站请求', 403);
      final p = r.uri.path;
      final ip = r.connectionInfo?.remoteAddress.address ?? 'unknown';
      final token = _bearer(r);
      if (p == '/ws' && WebSocketTransformer.isUpgradeRequest(r)) {
        _rate('ws:$ip', 100, 60);
        if (_allSockets.length >= 600) reject('连接数已达上限', 503);
        final ws = await _upgradeWebSocket(r);
        upgraded = true;
        _watch(ws);
        return;
      }
      if (p.startsWith('/api/')) {
        _rate('api:$ip', 3000, 60);
        if (r.method == 'GET') {
          switch (p) {
            case '/api/invitation':
              _requireAdmin(token);
              final link = await invitation(r);
              _json(r.response, {
                'url': link.url,
                'qr': _qrSvg(link.url),
                'localOnly':
                    link.base.host == 'localhost' ||
                    link.base.host.startsWith('127.'),
                'candidateCount': link.candidates.length,
              });
            case '/api/qr':
              _requireAdmin(token);
              final link = await invitation(r);
              final code = QrImage(
                QrCode.fromData(
                  data: link.url,
                  errorCorrectLevel: QrErrorCorrectLevel.M,
                ),
              );
              final size = code.moduleCount + 8;
              final svg = StringBuffer(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size"><rect width="$size" height="$size" fill="white"/><g fill="black">',
              );
              for (var y = 0; y < code.moduleCount; y++) {
                for (var x = 0; x < code.moduleCount; x++) {
                  if (code.isDark(y, x))
                    svg.write(
                      '<rect x="${x + 4}" y="${y + 4}" width="1" height="1"/>',
                    );
                }
              }
              svg.write('</g></svg>');
              r.response.headers.contentType = ContentType('image', 'svg+xml');
              r.response.write(svg);
            case '/api/health':
              _json(r.response, {
                'service': 'mubangumi-banjian',
                'protocol': 1,
                'capabilities': [
                  'snapshot-revision',
                  'bounded-comments',
                  'invalidation-updates',
                ],
              });
            case '/api/history':
              _requireAdmin(token);
              _json(r.response, {'events': store.history()});
            case '/api/state':
              final id = r.uri.queryParameters['event'] ?? '';
              final since = int.tryParse(r.uri.queryParameters['since'] ?? '');
              _json(
                r.response,
                _view(
                  id,
                  token,
                  _admin(token),
                  since: r.uri.queryParameters['epoch'] == _serverEpoch
                      ? since
                      : null,
                ),
              );
            case '/api/comments':
              final id = r.uri.queryParameters['event'] ?? '';
              final round = r.uri.queryParameters['round'] ?? '';
              final beforeText = r.uri.queryParameters['before'];
              final limitText = r.uri.queryParameters['limit'];
              if ((beforeText != null && int.tryParse(beforeText) == null) ||
                  (limitText != null && int.tryParse(limitText) == null))
                reject('分页参数无效');
              _json(
                r.response,
                store.commentsPage(
                  id,
                  round,
                  token: token,
                  admin: _admin(token),
                  before: beforeText == null ? null : int.parse(beforeText),
                  limit: limitText == null
                      ? RoomLimits.commentPageSize
                      : int.parse(limitText),
                ),
              );
            case '/api/export':
              _requireAdmin(token);
              final id = r.uri.queryParameters['event'] ?? '';
              final format = r.uri.queryParameters['format'];
              r.response.headers.set(
                'Content-Disposition',
                'attachment; filename="banjian-${format == 'json'
                    ? 'record.json'
                    : format == 'comments'
                    ? 'comments.csv'
                    : 'scores.csv'}"',
              );
              if (format == 'json') {
                r.response.headers.contentType = ContentType.json;
              } else {
                r.response.headers.contentType = ContentType(
                  'text',
                  'csv',
                  charset: 'utf-8',
                );
              }
              // Validate before sending response headers; streaming uses its
              // own read transaction so scores may continue during export.
              store.info(id);
              await r.response.addStream(
                store
                    .exportStream(id, format: format ?? 'scores')
                    .map(utf8.encode),
              );
            case '/api/search':
              _requireAdmin(token);
              _rate('search', 30, 60);
              final query = (r.uri.queryParameters['q'] ?? '').trim();
              if (query.isEmpty || query.length > 100) reject('请输入名称或条目 ID');
              _json(r.response, {'subjects': await search(query)});
            case '/api/subject':
              _requireAdmin(token);
              _rate('subject', 60, 60);
              final id = int.tryParse(r.uri.queryParameters['id'] ?? '') ?? 0;
              if (id <= 0) reject('条目 ID 无效');
              _json(r.response, await subject(id));
            default:
              reject('接口不存在', 404);
          }
        } else if (r.method == 'POST') {
          final c = await _body(r);
          switch (p) {
            case '/api/locate':
              _rate('locate:$ip', 120, 60);
              final id = textField(c, 'event', max: 64);
              final nonce = textField(c, 'nonce', max: 64);
              if (!RegExp(r'^[A-Za-z0-9_-]{24,64}$').hasMatch(nonce))
                reject('探测参数无效');
              final e = store.info(id);
              _json(r.response, {
                'service': 'mubangumi-banjian',
                'protocol': 1,
                'event': id,
                'proof': roomLocationProof(e['invite'], id, nonce),
              });
            case '/api/login':
              _rate('login:$ip', 10, 300);
              if (digest(textField(c, 'password', max: 256)) != _passwordHash)
                reject('管理密码错误', 403);
              _sessions.removeWhere(
                (_, expiry) => expiry.isBefore(DateTime.now()),
              );
              if (_sessions.length >= 50) reject('管理会话过多，请稍后重试', 429);
              final secret = newSecret();
              _sessions[digest(secret)] = DateTime.now().add(
                const Duration(hours: 12),
              );
              _json(r.response, {'token': secret});
            case '/api/logout':
              _sessions.remove(digest(token));
              _json(r.response, {'ok': true});
              _broadcast();
            case '/api/preview':
              _json(
                r.response,
                store.preview(textField(c, 'event'), textField(c, 'invite')),
              );
            case '/api/join':
              _rate('join:$ip', 100, 300);
              _json(r.response, store.join(c));
              _broadcast();
            case '/api/command':
              _rate('write:${digest(token)}', 120, 60);
              RoomCommand.fromJson(c, participant: true);
              _json(r.response, store.submit(token, c));
              _broadcast();
            case '/api/admin':
              _requireAdmin(token);
              RoomCommand.fromJson(c, participant: false);
              final result = store.admin(c);
              _json(r.response, result);
              _broadcast();
              if (autoCacheCovers && c['action'] == 'add')
                unawaited(repairCovers(result['id']));
            case '/api/repair-covers':
              _requireAdmin(token);
              final id = textField(c, 'event', max: 64);
              store.info(id);
              _rate('cover-retry:$id', 6, 60);
              unawaited(repairCovers(id));
              _json(r.response, {'queued': true});
            default:
              reject('接口不存在', 404);
          }
        } else {
          reject('请求方法不支持', 405);
        }
      } else if (r.method == 'GET' && p.startsWith('/cover/')) {
        final id = p.substring(7);
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) reject('封面不存在', 404);
        final cover = store.db.select(
          'SELECT mime,bytes FROM covers WHERE id=?',
          [id],
        );
        if (cover.isEmpty) reject('封面不存在', 404);
        r.response.headers.set('Content-Type', cover.single['mime']);
        r.response.add(cover.single['bytes'] as List<int>);
      } else if (r.method == 'GET') {
        final key = p == '/' || p == '/admin' || p.startsWith('/join/')
            ? 'index.html'
            : p.substring(1);
        final bytes = assets[key];
        if (bytes == null) reject('页面不存在', 404);
        r.response.headers.contentType = key.endsWith('.js')
            ? ContentType('text', 'javascript', charset: 'utf-8')
            : key.endsWith('.css')
            ? ContentType('text', 'css', charset: 'utf-8')
            : ContentType.html;
        r.response.add(bytes);
      } else {
        reject('页面不存在', 404);
      }
    } catch (e) {
      if (!upgraded) {
        final error = e is RoomError
            ? e
            : e is FormatException
            ? const RoomError(400, '数据格式无效')
            : const RoomError(500, '服务处理失败，请重试；未确认的操作不会显示成功');
        _json(r.response, {'error': error.message}, error.status);
      }
    } finally {
      if (!upgraded) {
        try {
          await r.response.close();
        } catch (_) {}
      }
    }
  }

  Json _view(String event, String token, bool admin, {int? since}) {
    final view = store.viewSince(event, since, token: token, admin: admin);
    view['serverEpoch'] = _serverEpoch;
    if (admin)
      view['connections'] = _sockets.values
          .where((s) => s.event == event && !s.admin)
          .length;
    return view;
  }

  void _watch(WebSocket ws) {
    // Upgrading detaches the connection from HttpServer and awaits a handshake.
    // Shutdown may have already swept the sockets while that await was pending.
    if (_closed) {
      unawaited(ws.close(1001, '服务已停止'));
      return;
    }
    _allSockets.add(ws);
    ws.pingInterval = const Duration(seconds: 20);
    final timeout = Timer(const Duration(seconds: 8), () {
      if (!_sockets.containsKey(ws)) unawaited(ws.close(1008, '请先认证'));
    });
    ws.listen(
      (message) {
        try {
          if (message is! String ||
              message.length > 2048 ||
              _sockets.containsKey(ws))
            reject('无效连接消息');
          final c = jsonDecode(message) as Json;
          final token = textField(c, 'token', max: 128);
          final id = textField(c, 'event');
          final admin = _admin(token);
          store.view(id, token: token, admin: admin);
          _sockets[ws] = (
            event: id,
            token: token,
            admin: admin,
            invalidate: c['updates'] == 'invalidate',
          );
          timeout.cancel();
          final initial = _view(id, token, admin);
          _socketVersions[ws] = initial['version'] as int;
          ws.add(jsonEncode(initial));
          _broadcast();
        } catch (_) {
          unawaited(ws.close(1008, '认证失败'));
        }
      },
      onDone: () {
        timeout.cancel();
        _allSockets.remove(ws);
        _socketVersions.remove(ws);
        _sockets.remove(ws);
        _broadcast();
      },
      onError: (Object _) {
        timeout.cancel();
        _allSockets.remove(ws);
        _socketVersions.remove(ws);
        _sockets.remove(ws);
      },
      cancelOnError: true,
    );
  }

  void _broadcast() {
    if (_closed || _broadcastTimer?.isActive == true) return;
    _broadcastTimer = Timer(const Duration(milliseconds: 80), _broadcastNow);
  }

  void _broadcastNow() {
    if (_closed) return;
    final metadata = <String, Json>{};
    for (final entry in _sockets.entries.toList()) {
      try {
        final s = entry.value;
        final info = metadata.putIfAbsent(s.event, () => store.header(s.event));
        if (s.admin) _requireAdmin(s.token);
        if (!s.admin) store.participant({'id': s.event}, s.token);
        entry.key.add(
          jsonEncode(
            s.invalidate && _socketVersions[entry.key] == info['version']
                ? {
                    'type': 'invalidate',
                    'event': s.event,
                    'revision': store.revision(s.event),
                  }
                : _view(s.event, s.token, s.admin),
          ),
        );
        _socketVersions[entry.key] = info['version'] as int;
      } catch (_) {
        unawaited(entry.key.close(1008, '会话已失效'));
      }
    }
  }

  Future<Object> _bangumi(String path, {Json? body}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .openUrl(
            body == null ? 'GET' : 'POST',
            Uri.parse('https://api.bgm.tv/v0/$path'),
          )
          .timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set(
        'User-Agent',
        'MuBangumi-Banjian/1.0 (https://github.com/wweiyi/MuBangumi)',
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) reject('Bangumi 暂不可用；可从本机收藏导入快照', 502);
      final bytes = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.add(chunk);
        if (bytes.length > 2 * 1024 * 1024) reject('条目数据过大', 502);
      }
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } finally {
      client.close(force: true);
    }
  }

  Json _subject(Json raw) => {
    'id': raw['id'],
    'title': (raw['name_cn'] as String? ?? '').isNotEmpty
        ? raw['name_cn']
        : raw['name'],
    'summary': (raw['summary'] as String? ?? '').substring(
      0,
      (raw['summary'] as String? ?? '').length.clamp(0, 6000),
    ),
    'cover': '',
  };
  Future<List<Json>> search(String query) async {
    final id = int.tryParse(query);
    if (id != null && id > 0) {
      final raw = await _bangumi('subjects/$id') as Json;
      return raw['type'] == 2 ? [_subject(raw)] : [];
    }
    final result =
        await _bangumi(
              'search/subjects?limit=20',
              body: {
                'keyword': query,
                'filter': {
                  'type': [2],
                },
                'sort': 'match',
              },
            )
            as Json;
    return (result['data'] as List).cast<Json>().map(_subject).toList();
  }

  Future<Json> subject(int id) async {
    final raw = await _bangumi('subjects/$id') as Json;
    if (raw['type'] != 2) reject('请选择动画条目');
    final data = _subject(raw);
    final image = raw['images']?['common'] ?? raw['images']?['large'];
    data['coverSource'] = image is String
        ? roomCoverUri(image)?.toString() ?? ''
        : '';
    try {
      data['cover'] = await coverCache.ensure(data);
    } catch (_) {
      data['coverWarning'] = '封面暂未缓存，可在管理页重试补全';
    }
    return data;
  }
}
