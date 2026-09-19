import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'room_storage.dart';
export 'room_storage.dart';
import 'room_discovery.dart';
import '../../core/diagnostics/async_diagnostics.dart';

Json _decodeRoomResponse(Uint8List bytes) {
  final data = jsonDecode(utf8.decode(bytes));
  if (data is! Json) throw const FormatException('Invalid room response');
  return data;
}

class RoomApi {
  RoomApi(this.base, {this.token = ''});
  final Uri base;
  String token;
  final _snapshots = <String, Json>{};
  void rememberSnapshot(Json snapshot) {
    final id = snapshot['id'];
    if (id is! String || snapshot['revision'] is! int) return;
    final key = '${digest(token)}:$id';
    final old = _snapshots[key];
    if (old != null &&
        sameRoomEpoch(old, snapshot) &&
        (old['revision'] as int) > (snapshot['revision'] as int)) {
      return;
    }
    _snapshots.remove(key);
    _snapshots[key] = snapshot;
    while (_snapshots.length > 8) {
      _snapshots.remove(_snapshots.keys.first);
    }
  }

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
    final uri = Uri.parse(path);
    if (body != null || uri.path != 'state') return _request(path, body);
    final requestToken = token;
    final previous =
        _snapshots['${digest(token)}:${uri.queryParameters['event']}'];
    final query = previous == null
        ? path
        : uri
              .replace(
                queryParameters: {
                  ...uri.queryParameters,
                  'since': '${previous['revision']}',
                  if (previous['serverEpoch'] is String)
                    'epoch': previous['serverEpoch'] as String,
                },
              )
              .toString();
    final payload = await _request(query);
    Json snapshot;
    try {
      snapshot = mergeRoomSnapshot(previous, payload);
    } on FormatException {
      if (payload['type'] != 'delta') rethrow;
      snapshot = mergeRoomSnapshot(null, await _request(path));
    }
    final currentCache =
        _snapshots['${digest(requestToken)}:${uri.queryParameters['event']}'];
    if (token == requestToken &&
        (currentCache == null ||
            sameRoomEpoch(currentCache, previous ?? {}) ||
            sameRoomEpoch(currentCache, snapshot))) {
      rememberSnapshot(snapshot);
    }
    return snapshot;
  }

  Future<Json> _request(String path, [Json? body]) async {
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
      final content = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        content.add(chunk);
        if (content.length > RoomLimits.snapshotBytes) {
          throw const RoomError(502, '活动数据过大');
        }
      }
      final bytes = content.takeBytes();
      final data = bytes.length > 128 * 1024
          ? await compute(_decodeRoomResponse, bytes)
          : _decodeRoomResponse(bytes);
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

final participationProvider = ChangeNotifierProvider<ParticipationController>((
  ref,
) {
  final controller = ParticipationController();
  unawaited(controller.restore());
  return controller;
});

class ParticipationController extends ChangeNotifier {
  ParticipationController({ParticipationStorage? storage})
    : storage = storage ?? RoomLocalStorage();
  final ParticipationStorage storage;
  final diagnostics = AsyncDiagnostics();
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
  Timer? _liveRefresh;
  int _activeReads = 0, _announcedRevision = 0;
  bool _liveDirty = false;
  bool _connectionError = false;
  DateTime? _snapshotSavedAt;
  bool online = false, busy = false, _flushing = false, _disposed = false;
  int _generation = 0;
  int _requestEpoch = 0, _liveRevision = 0;
  Future<void>? _connecting;
  int? _connectingGeneration;
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
      if (generation == _generation && !_disposed) {
        if (storage is ArchivedParticipationStorage) value.remove('snapshot');
        _saved = value;
      }
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
        if (storage is ArchivedParticipationStorage) _saved.remove('snapshot');
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
      _activeReads = 0;
      _announcedRevision = 0;
      _liveDirty = false;
      _liveRefresh?.cancel();
      _snapshotSavedAt = null;
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
      var restored = restoreKey == null ? null : archives.remove(restoreKey);
      if (!same &&
          storage is ArchivedParticipationStorage &&
          (restored == null ||
              restored is Json && restored['stored'] == true)) {
        restored = await (storage as ArchivedParticipationStorage).readRoom(
          target.identityKey,
        );
      }
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
      if (storage is ArchivedParticipationStorage) {
        data['archives'] = {
          for (final entry in archives.entries)
            entry.key: {
              'url': entry.value['url'],
              'token': entry.value['token'],
              'stored': true,
            },
        };
        data.remove('snapshot');
      }
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
    _activeReads = 0;
    _announcedRevision = 0;
    _liveDirty = false;
    _liveRefresh?.cancel();
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
    final request = ++_requestEpoch;
    final timer = Stopwatch()..start();
    diagnostics.record(
      AsyncEvent.readStarted,
      request: request,
      generation: generation,
    );
    final liveRevision = _liveRevision;
    _activeReads++;
    bool currentRequest() =>
        !_disposed && generation == _generation && request == _requestEpoch;
    try {
      if (!online && invite!.candidates.length > 1) {
        final found = await locate(invite!);
        if (!currentRequest()) return;
        invite = found.invite;
        api = RoomApi(invite!.base, token: api!.token);
        await _mutate((value) => value['url'] = invite!.url);
      }
      final data = await api!.request('state?event=${invite!.eventId}');
      if (!currentRequest()) {
        diagnostics.record(
          AsyncEvent.readSuperseded,
          request: request,
          generation: generation,
        );
        return;
      }
      if (sameRoomEpoch(event, data) &&
          data['revision'] is int &&
          (data['revision'] as int) < _announcedRevision) {
        _liveDirty = true;
      }
      // A live update delivered after this HTTP read began is authoritative
      // unless the response carries a strictly newer server snapshot revision.
      final newer =
          sameRoomEpoch(event, data) &&
          (data['revision'] as int? ?? -1) > (event?['revision'] as int? ?? -1);
      if (_liveRevision == liveRevision || newer) _acceptSnapshot(data);
      online = true;
      if (_connectionError) message = null;
      _connectionError = false;
      // Snapshot persistence is best effort; command persistence is mandatory.
      if (storage is! ArchivedParticipationStorage ||
          _snapshotSavedAt == null ||
          DateTime.now().difference(_snapshotSavedAt!) >=
              const Duration(seconds: 2)) {
        _snapshotSavedAt = DateTime.now();
        unawaited(
          _mutate((value) {
            if (!currentRequest()) return;
            value['snapshot'] = event;
            value['name'] = event?['name'];
          }).catchError((Object _) {}),
        );
      }
      _notify();
      await _connect(generation);
      diagnostics.record(
        AsyncEvent.readAccepted,
        request: request,
        revision: event?['revision'] as int?,
        elapsedMs: timer.elapsedMilliseconds,
      );
      if (currentRequest()) unawaited(_flush());
    } catch (e) {
      if (!currentRequest() || _liveRevision != liveRevision) {
        diagnostics.record(
          AsyncEvent.readSuperseded,
          request: request,
          generation: generation,
        );
        return;
      }
      diagnostics.record(
        e is FormatException
            ? AsyncEvent.invalidPayload
            : AsyncEvent.readFailed,
        request: request,
        elapsedMs: timer.elapsedMilliseconds,
        status: e is RoomError ? e.status : null,
      );
      online = false;
      _connectionError = true;
      message = e is RoomError
          ? e.message
          : e is FormatException
          ? '活动数据格式不兼容，请检查服务端版本后重试；未确认的输入已保留'
          : '连接中断，正在重连；未确认的输入已保留';
      _notify();
      _schedule();
    } finally {
      if (generation == _generation) {
        _activeReads--;
        if (_activeReads == 0 && _liveDirty && !_disposed) {
          _requestLiveRefresh();
        }
      }
    }
  }

  bool _acceptSnapshot(Json next) {
    final snapshot = RoomSnapshot.fromJson(next);
    if (snapshot.id != invite?.eventId) {
      throw const FormatException('Unexpected room');
    }
    if (event?['id'] == next['id'] &&
        sameRoomEpoch(event, next) &&
        next['revision'] is int &&
        event?['revision'] is int &&
        (next['revision'] as int) < (event!['revision'] as int)) {
      return false;
    }
    if (!sameRoomEpoch(event, next)) _announcedRevision = 0;
    event = snapshot.toJson();
    api?.rememberSnapshot(event!);
    return true;
  }

  void _requestLiveRefresh() {
    _liveDirty = true;
    if (_activeReads > 0 || _liveRefresh?.isActive == true) return;
    final generation = _generation;
    _liveRefresh = Timer(const Duration(milliseconds: 60), () {
      if (generation != _generation || _disposed) return;
      _liveDirty = false;
      unawaited(refresh());
    });
  }

  void _schedule() {
    _retry?.cancel();
    if (active && !_disposed) {
      _retry = Timer(const Duration(seconds: 3), () => unawaited(refresh()));
    }
  }

  Future<void> _connect(int generation) async {
    if (_socket?.readyState == WebSocket.open) return;
    if (_connecting != null && _connectingGeneration == generation) {
      return _connecting!;
    }
    final future = _openSocket(generation);
    _connecting = future;
    _connectingGeneration = generation;
    try {
      await future;
    } finally {
      if (identical(_connecting, future)) _connecting = null;
    }
  }

  Future<void> _openSocket(int generation) async {
    final base = invite!.base;
    final token = api!.token;
    final eventId = invite!.eventId;
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
    ws.add(
      jsonEncode({'token': token, 'event': eventId, 'updates': 'invalidate'}),
    );
    void disconnected() {
      if (generation != _generation || _disposed || !identical(_socket, ws)) {
        return;
      }
      _socket = null;
      online = false;
      _notify();
      _schedule();
    }

    ws.listen(
      (raw) {
        if (generation != _generation || _disposed || !identical(_socket, ws)) {
          return;
        }
        try {
          final next = jsonDecode(raw as String) as Json;
          if (next['type'] == 'invalidate') {
            if (next['event'] != invite!.eventId || next['revision'] is! int) {
              return;
            }
            _announcedRevision = (next['revision'] as int) > _announcedRevision
                ? next['revision'] as int
                : _announcedRevision;
            _liveRevision++;
            online = true;
            _requestLiveRefresh();
            return;
          }
          if (!_acceptSnapshot(next)) return;
          _liveRevision++;
          online = true;
          if (_connectionError) message = null;
          _connectionError = false;
          _notify();
          unawaited(_flush());
        } catch (_) {
          _connectionError = true;
          message = '活动数据格式无效，正在重新读取；未确认的输入已保留';
          _notify();
          unawaited(ws.close(1002, 'Invalid room snapshot'));
        }
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
    RoomCommand.fromJson(c, participant: true);
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
          diagnostics.record(
            AsyncEvent.commandConfirmed,
            generation: generation,
            pending: pending.length,
          );
        } catch (e) {
          if (generation != _generation) return;
          if (e is! RoomError || e.status >= 500 || e.status == 429) {
            online = false;
            _connectionError = true;
            diagnostics.record(
              AsyncEvent.commandPending,
              generation: generation,
              pending: pending.length,
              status: e is RoomError ? e.status : null,
            );
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
    _liveRefresh?.cancel();
    unawaited(_socket?.close());
    super.dispose();
  }
}
