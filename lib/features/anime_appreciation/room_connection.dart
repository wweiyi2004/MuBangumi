import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'room_discovery.dart';

class RoomApi {
  RoomApi(this.base, {this.token = ''});
  final Uri base;
  String token;
  Future<Uint8List> download(String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(base.resolve('/api/$path'))
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set('Authorization', 'Bearer $token');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        throw RoomError(response.statusCode, '导出失败，请刷新或重新连接管理端');
      }
      final bytes = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.add(chunk);
        if (bytes.length > 32 * 1024 * 1024) {
          throw const RoomError(413, '导出记录超过本机内存导出限制，请使用网页管理端导出');
        }
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<Json> request(String path, [Json? body]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final r = await client
          .openUrl(body == null ? 'GET' : 'POST', base.resolve('/api/$path'))
          .timeout(const Duration(seconds: 10));
      r.followRedirects = false;
      r.headers.contentType = ContentType.json;
      if (token.isNotEmpty) r.headers.set('Authorization', 'Bearer $token');
      if (body != null) r.write(jsonEncode(body));
      final response = await r.close().timeout(const Duration(seconds: 15));
      final content = StringBuffer();
      await for (final chunk
          in response
              .transform(utf8.decoder)
              .timeout(const Duration(seconds: 15))) {
        content.write(chunk);
        if (content.length > 8 * 1024 * 1024) {
          throw const RoomError(502, '活动数据过大');
        }
      }
      final data = jsonDecode(content.toString());
      if (data is! Json) throw const RoomError(502, '服务数据无效');
      if (response.statusCode != 200) {
        throw RoomError(
          response.statusCode,
          data['error']?.toString() ?? '连接失败',
        );
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }
}

abstract class ParticipationStorage {
  Future<Json?> read();
  Future<void> write(Json value);
}

class SecureParticipationStorage implements ParticipationStorage {
  const SecureParticipationStorage({this.key = 'banjian_participation_v1'});
  final String key;
  static const _storage = FlutterSecureStorage();
  @override
  Future<Json?> read() async {
    final text = await _storage.read(key: key);
    return text == null ? null : jsonDecode(text) as Json;
  }

  @override
  Future<void> write(Json value) =>
      _storage.write(key: key, value: jsonEncode(value));
}

final participationProvider = ChangeNotifierProvider<ParticipationController>((
  ref,
) {
  final controller = ParticipationController();
  unawaited(controller.restore());
  return controller;
});

class ParticipationController extends ChangeNotifier {
  ParticipationController({ParticipationStorage? storage})
    : storage = storage ?? const SecureParticipationStorage();
  final ParticipationStorage storage;
  final _located = <String, RoomInvite>{};
  final _discoveries = <RoomDiscovery>{};
  RoomInvite resolvedInviteFor(RoomInvite target) =>
      _located[target.identityKey] ?? target;
  Future<LocatedRoom> locate(RoomInvite target) async {
    final discovery = RoomDiscovery();
    _discoveries.add(discovery);
    try {
      final result = await discovery.find(target);
      if (_disposed) throw const RoomError(499, '页面已关闭');
      if (_located.length >= 16) _located.clear();
      _located[target.identityKey] = result.invite;
      return result;
    } finally {
      _discoveries.remove(discovery);
      discovery.close();
    }
  }

  Json _saved = {};
  Json? event;
  RoomInvite? invite;
  RoomApi? api;
  WebSocket? _socket;
  Timer? _retry;
  bool online = false, busy = false, _flushing = false, _disposed = false;
  int _generation = 0;
  String? message;
  Future<void> _writes = Future.value();
  bool get active => _saved['active'] == true && invite != null;
  bool hasIdentity(RoomInvite target) =>
      (target.sameRoom(invite) && _saved['token'] != null) ||
      ((_saved['archives'] as Json?)?.values.any(
            (record) =>
                record is Json &&
                target.sameRoom(
                  RoomInvite.parse(record['url'] as String? ?? ''),
                ),
          ) ??
          false);
  String get name => _saved['name'] as String? ?? '';
  List<Json> get pending => ((_saved['pending'] as List?) ?? []).cast<Json>();
  Json get drafts => (_saved['drafts'] as Json?) ?? {};
  List<Json> get rounds => ((event?['rounds'] as List?) ?? []).cast<Json>();
  Json? get current {
    for (final r in rounds) {
      if (r['id'] == event?['current']) return r;
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist(Json value) {
    final copy = clone(value);
    final next = _writes.then((_) => storage.write(copy));
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _mutate(void Function(Json) edit) {
    final generation = _generation;
    final next = _writes.then((_) async {
      if (_disposed || generation != _generation) return;
      final value = clone(_saved);
      edit(value);
      await storage.write(value);
      if (generation == _generation && !_disposed) _saved = value;
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> restore() async {
    final generation = _generation;
    try {
      final value = await storage.read();
      if (_disposed || generation != _generation || value == null) return;
      _saved = value;
      invite = RoomInvite.parse(value['url'] as String? ?? '');
      if (invite != null) {
        api = RoomApi(invite!.base, token: value['token'] as String? ?? '');
        event = value['snapshot'] as Json?;
        if (active) unawaited(refresh());
      }
      _notify();
    } catch (_) {
      message = '本地参与记录读取失败，请重试';
      _notify();
    }
  }

  Future<Json> preview(RoomInvite target) async =>
      (await locate(target)).preview;
  Future<void> join(RoomInvite target, String name) async {
    if (busy) return;
    if (name.trim().isEmpty || name.runes.length > 40) {
      throw const RoomError(400, '请填写 1–40 字的活动显示名');
    }
    busy = true;
    _notify();
    try {
      target = resolvedInviteFor(target);
      if (!_located.containsKey(target.identityKey)) {
        target = (await locate(target)).invite;
      }
      ++_generation;
      await _writes;
      _retry?.cancel();
      await _socket?.close();
      _socket = null;
      final same = target.sameRoom(invite);
      final archives = clone((_saved['archives'] as Json?) ?? {});
      if (!same && invite != null) {
        final old = clone(_saved)..remove('archives');
        archives[invite!.identityKey] = old;
      }
      final restoreKey = archives.keys.where((key) {
        final record = archives[key];
        return record is Json &&
            target.sameRoom(RoomInvite.parse(record['url'] as String? ?? ''));
      }).firstOrNull;
      final restored = restoreKey == null ? null : archives.remove(restoreKey);
      final data = same
          ? clone(_saved)
          : restored is Json
          ? restored
          : <String, dynamic>{
              'token': newSecret(),
              'op': newSecret(),
              'pending': <dynamic>[],
              'drafts': <String, dynamic>{},
            };
      data.addAll({
        'url': target.url,
        'name': name.trim(),
        'active': false,
        'archives': archives,
        'op': newSecret(),
      });
      // Save token before sending join; retrying after a lost response recovers
      // the same participant rather than registering a second identity.
      await _persist(data);
      _saved = data;
      invite = target;
      final client = RoomApi(target.base, token: data['token']);
      api = client;
      await client.request('join', {
        'op': data['op'],
        'event': target.eventId,
        'invite': target.secret,
        'token': data['token'],
        'name': data['name'],
      });
      await _mutate((value) => value['active'] = true);
      await refresh();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> leave() async {
    ++_generation;
    _retry?.cancel();
    await _socket?.close();
    _socket = null;
    await _mutate((value) => value['active'] = false);
    online = false;
    _notify();
  }

  Future<void> refresh() async {
    if (!active || _disposed) return;
    final generation = _generation;
    try {
      if (!online && invite!.candidates.length > 1) {
        final found = await locate(invite!);
        if (generation != _generation || _disposed) return;
        invite = found.invite;
        api = RoomApi(invite!.base, token: api!.token);
        await _mutate((value) => value['url'] = invite!.url);
      }
      final data = await api!.request('state?event=${invite!.eventId}');
      if (generation != _generation || _disposed) return;
      event = data;
      online = true;
      message = null;
      // Snapshot persistence is best effort; command persistence is mandatory.
      unawaited(
        _mutate((value) {
          value['snapshot'] = data;
          value['name'] = data['name'];
        }).catchError((Object _) {}),
      );
      _notify();
      await _connect(generation);
      unawaited(_flush());
    } catch (e) {
      if (generation != _generation || _disposed) return;
      online = false;
      message = e is RoomError ? e.message : '连接中断，正在重连；未确认的输入已保留';
      _notify();
      _schedule();
    }
  }

  void _schedule() {
    _retry?.cancel();
    if (active && !_disposed) {
      _retry = Timer(const Duration(seconds: 3), () => unawaited(refresh()));
    }
  }

  Future<void> _connect(int generation) async {
    if (_socket?.readyState == WebSocket.open) return;
    final base = invite!.base;
    final ws = await WebSocket.connect(
      base
          .resolve('/ws')
          .replace(scheme: base.scheme == 'https' ? 'wss' : 'ws')
          .toString(),
    ).timeout(const Duration(seconds: 10));
    if (generation != _generation || _disposed) {
      await ws.close();
      return;
    }
    _socket = ws;
    ws.pingInterval = const Duration(seconds: 20);
    ws.add(jsonEncode({'token': api!.token, 'event': invite!.eventId}));
    void disconnected() {
      if (generation != _generation || _disposed) return;
      _socket = null;
      online = false;
      _notify();
      _schedule();
    }

    ws.listen(
      (raw) {
        if (generation != _generation || _disposed) return;
        try {
          final next = jsonDecode(raw as String) as Json;
          if (next['id'] != invite!.eventId) return;
          event = next;
          online = true;
          _notify();
          unawaited(_flush());
        } catch (_) {}
      },
      onDone: disconnected,
      onError: (Object _) => disconnected(),
      cancelOnError: true,
    );
  }

  Future<void> saveDraft(String round, {String? text, int? score}) async {
    await _mutate((next) {
      final values =
          next.putIfAbsent('drafts', () => <String, dynamic>{}) as Json;
      values[round] = {
        ...?values[round] as Json?,
        'text': ?text,
        'score': ?score,
      };
    });
  }

  Future<void> submit(
    String action, {
    int? score,
    String? text,
    String? roundId,
  }) async {
    final r = current;
    if (r == null ||
        (roundId != null && r['id'] != roundId) ||
        r['status'] != 'open' ||
        event?['ended'] == true) {
      throw const RoomError(409, '本轮已暂停或截止，输入已保留');
    }
    if (pending.length >= 100) throw const RoomError(409, '待确认操作过多，请先恢复连接');
    if (action == 'comment' &&
        pending.any((c) => c['round'] == r['id'] && c['text'] == text)) {
      throw const RoomError(409, '这条短评正在等待确认');
    }
    final c = <String, dynamic>{
      'op': newSecret(),
      'event': event!['id'],
      'round': r['id'],
      'action': action,
      'score': ?score,
      'text': ?text,
    };
    await _mutate((next) {
      final values = next['pending'] as List;
      if (values.length >= 100) throw const RoomError(409, '待确认操作过多');
      if (action == 'comment' &&
          values.any((v) => v['round'] == c['round'] && v['text'] == text)) {
        throw const RoomError(409, '这条短评正在等待确认');
      }
      values.add(c);
    });
    message = '已保存，等待服务确认';
    _notify();
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_flushing || !online || !active || _disposed) return;
    _flushing = true;
    final generation = _generation;
    try {
      while (pending.isNotEmpty &&
          online &&
          generation == _generation &&
          !_disposed) {
        final c = pending.first;
        var accepted = false;
        try {
          await api!.request('command', c);
          accepted = true;
        } catch (e) {
          if (generation != _generation) return;
          if (e is! RoomError || e.status >= 500 || e.status == 429) {
            online = false;
            message = '提交尚未确认，恢复连接后将自动核对';
            _schedule();
            break;
          }
          message = '${e.message}；原输入已保留';
        }
        if (generation != _generation || _disposed) return;
        await _mutate((next) {
          (next['pending'] as List).removeWhere((v) => v['op'] == c['op']);
          if (accepted) {
            message = c['action'] == 'score' ? '评分已确认' : '匿名短评已确认';
            if (c['action'] == 'comment' &&
                next['drafts']?[c['round']]?['text'] == c['text']) {
              next['drafts'][c['round']]['text'] = '';
            }
          }
        });
      }
    } catch (_) {
      message = '本地确认记录保存失败，操作将在重连后再次核对';
      _schedule();
    } finally {
      _flushing = false;
      _notify();
      if (generation != _generation && active && online && pending.isNotEmpty) {
        unawaited(_flush());
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final discovery in _discoveries.toList()) {
      discovery.close();
    }
    ++_generation;
    _retry?.cancel();
    unawaited(_socket?.close());
    super.dispose();
  }
}
