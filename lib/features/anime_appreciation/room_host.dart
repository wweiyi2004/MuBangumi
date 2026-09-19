import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'room_connection.dart';

final roomHostProvider = ChangeNotifierProvider<RoomHost>((ref) => RoomHost());

class RoomHost extends ChangeNotifier {
  static const _channel = MethodChannel('mubangumi/banjian');
  RoomHost({
    Future<Directory> Function()? directory,
    ParticipationStorage? commandStorage,
    this.port = 43928,
    this.autoCacheCovers = true,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _commandStorage =
           commandStorage ??
           RoomLocalStorage(key: 'banjian_admin_commands_v1') {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'stopRequested') await stop();
      });
    }
  }
  final Future<Directory> Function() _directory;
  final int port;
  final bool autoCacheCovers;
  final ParticipationStorage _commandStorage;
  Json _commandRecords = {};
  Json? _pendingAdmin;
  bool _commandBusy = false;
  int _generation = 0;
  bool get hasPendingCommand => _pendingAdmin != null;
  String get _commandKey => remote ? base!.origin : 'local';
  Future<void> _loadCommands() async {
    _commandRecords = await _commandStorage.read() ?? {};
    _pendingAdmin = _commandRecords[_commandKey] as Json?;
  }

  Future<void> _saveCommand(Json? command) async {
    final next = clone(_commandRecords);
    if (command == null) {
      next.remove(_commandKey);
    } else {
      next[_commandKey] = command;
    }
    await _commandStorage.write(next);
    _commandRecords = next;
    _pendingAdmin = command;
    _notify();
  }

  Isolate? _isolate;
  ReceivePort? _receive;
  SendPort? _control;
  Completer<void>? _stopped;
  bool running = false, busy = false, remote = false;
  String? error, password;
  String? networkNotice;
  Uri? base;
  RoomApi? api;
  List<String> addresses = [];
  List<RoomShareAddress> networkAddresses = [];
  String addressLabel(String address) => address.startsWith('http://127.')
      ? '仅本机'
      : networkAddresses
                .where((v) => v.address == address)
                .firstOrNull
                ?.label ??
            (remote ? '在线服务器' : '局域网');
  RoomInvite makeInvite({String? preferred}) {
    if (event == null || event!['ended'] == true) {
      throw const RoomError(409, '这场活动已结束，请切换到正在进行的活动后重新邀请。');
    }
    final selected = Uri.parse(preferred ?? addresses.first);
    return RoomInvite(
      selected,
      event!['id'],
      event!['invite'],
      alternates: remote ? const [] : addresses.map(Uri.parse).toList(),
    );
  }

  Future<RoomInvite> prepareInvite({String? preferred}) async {
    await refresh(wait: true);
    final local = makeInvite(preferred: preferred);
    final response = await api!.request('invitation?event=${local.eventId}');
    final verified = RoomInvite.parse(response['url'] as String? ?? '');
    if (verified == null ||
        verified.eventId != local.eventId ||
        event?['id'] != local.eventId ||
        event?['ended'] == true) {
      throw const RoomError(409, '活动已变化，请重新点击邀请参与。');
    }
    return RoomInvite(
      local.base,
      verified.eventId,
      verified.secret,
      alternates: local.alternates,
    );
  }

  List<Json> history = [];
  DateTime? _historyLoadedAt;
  RoomApi? _historyClient;
  Json? event;
  WebSocket? _liveSocket;
  String? _liveKey;
  int _liveEpoch = 0;
  bool liveConnected = false;
  bool _openingSocket = false;
  Timer? _poll;
  bool _polling = false, _disposed = false;
  bool _refreshAfterPoll = false;
  int _announcedRevision = 0;
  String? _historySelection;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _watchLive() async {
    if (!running || api == null || event == null || _disposed) return;
    final id = event!['id'] as String;
    final key = '${api!.base.origin}:$id:${digest(api!.token)}';
    if (_liveKey == key &&
        (_openingSocket || _liveSocket?.readyState == WebSocket.open)) {
      return;
    }
    final epoch = ++_liveEpoch, generation = _generation;
    _announcedRevision = 0;
    final client = api!;
    unawaited(_liveSocket?.close());
    _liveSocket = null;
    _liveKey = key;
    _openingSocket = true;
    liveConnected = false;
    try {
      final ws = await WebSocket.connect(
        client.base
            .resolve('/ws')
            .replace(scheme: client.base.scheme == 'https' ? 'wss' : 'ws')
            .toString(),
      ).timeout(const Duration(seconds: 10));
      if (_disposed || generation != _generation || epoch != _liveEpoch) {
        await ws.close();
        return;
      }
      _liveSocket = ws;
      ws.pingInterval = const Duration(seconds: 20);
      void disconnected() {
        if (_disposed || epoch != _liveEpoch) return;
        _liveSocket = null;
        _liveKey = null;
        liveConnected = false;
        _notify();
      }

      ws.listen(
        (raw) {
          if (_disposed || epoch != _liveEpoch || generation != _generation) {
            return;
          }
          try {
            final next = jsonDecode(raw as String) as Json;
            if (next['type'] == 'invalidate') {
              if (next['event'] != event?['id'] || next['revision'] is! int) {
                return;
              }
              _announcedRevision =
                  (next['revision'] as int) > _announcedRevision
                  ? next['revision'] as int
                  : _announcedRevision;
              liveConnected = true;
              if (_polling) {
                _refreshAfterPoll = true;
              } else {
                unawaited(refresh(wait: false));
              }
              return;
            }
            final parsed = RoomSnapshot.fromJson(next);
            if (next['id'] != event?['id'] ||
                (sameRoomEpoch(event, next) &&
                    (parsed.version < (event?['version'] as int? ?? 0) ||
                        (parsed.revision) <
                            (event?['revision'] as int? ??
                                event?['version'] as int? ??
                                0)))) {
              return;
            }
            if (!sameRoomEpoch(event, next)) _announcedRevision = 0;
            event = parsed.toJson();
            client.rememberSnapshot(event!);
            liveConnected = true;
            error = null;
            _notify();
            if (next['ended'] == true && _historySelection == null) {
              unawaited(refresh(wait: false));
            }
          } catch (_) {
            error = '活动数据格式无效，请刷新或检查服务端版本';
            _notify();
            unawaited(ws.close(1002, 'Invalid room snapshot'));
          }
        },
        onDone: disconnected,
        onError: (Object _) => disconnected(),
        cancelOnError: true,
      );
      ws.add(
        jsonEncode({
          'event': id,
          'token': client.token,
          'updates': 'invalidate',
        }),
      );
    } catch (_) {
      if (epoch == _liveEpoch) _liveKey = null;
    } finally {
      if (epoch == _liveEpoch) _openingSocket = false;
    }
  }

  Future<void> start() async {
    if (busy || running) return;
    busy = true;
    ++_generation;
    networkNotice = null;
    addresses = [];
    event = null;
    _historySelection = null;
    history = [];
    error = null;
    _notify();
    try {
      if (Platform.isIOS) {
        throw const RoomError(400, 'iOS 暂支持参与和远程管理，请使用 Windows / Android 托管服务');
      }
      if (Platform.isAndroid) await _channel.invokeMethod<void>('start');
      final directory = await _directory();
      final data = Directory('${directory.path}/banjian')
        ..createSync(recursive: true);
      final assets = <String, List<int>>{};
      for (final name in [
        'index.html',
        'app.css',
        'room_protocol.js',
        'app.js',
      ]) {
        final bytes = await rootBundle.load(
          'packages/banjian_server/web/$name',
        );
        assets[name] = bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      }
      password = newSecret(12);
      _receive = ReceivePort();
      final ready = Completer<int>();
      _stopped = Completer<void>();
      _receive!.listen((data) {
        if (data is SendPort) _control = data;
        if (data is int && !ready.isCompleted) ready.complete(data);
        if (data is String && !ready.isCompleted) {
          ready.completeError(RoomError(500, data));
        }
        if (data == null) {
          if (!ready.isCompleted) {
            ready.completeError(const RoomError(500, '活动服务启动失败'));
          }
          if (!_stopped!.isCompleted) _stopped!.complete();
          if (running) {
            running = false;
            error = '活动服务已停止，已确认数据保留';
            _poll?.cancel();
            _notify();
          }
        }
      });
      _isolate = await Isolate.spawn(_hostMain, {
        'send': _receive!.sendPort,
        'path': '${data.path}/banjian.sqlite',
        'password': password,
        'assets': assets,
        'port': port,
        'autoCacheCovers': autoCacheCovers,
      }, onExit: _receive!.sendPort);
      final actualPort = await ready.future.timeout(
        const Duration(seconds: 20),
      );
      base = Uri.parse('http://127.0.0.1:$actualPort');
      api = RoomApi(base!);
      api!.token = (await api!.request('login', {
        'password': password,
      }))['token'];
      remote = false;
      running = true;
      await _loadCommands();
      await refreshAddresses();
      await refresh();
      _beginPoll();
    } catch (e) {
      error = e is SocketException
          ? '端口 43928 已占用或网络不可用，请停止其他番键会服务后重试'
          : e.toString();
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      running = false;
      if (Platform.isAndroid) await _channel.invokeMethod<void>('stop');
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> connectRemote(Uri uri, String adminPassword) async {
    if (running && !remote) throw const RoomError(409, '请先停止本机服务');
    if (!validServerUri(uri) ||
        uri.path != '/' && uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const RoomError(400, '请输入 HTTPS 服务地址，局域网可使用 HTTP IP 地址');
    }
    busy = true;
    ++_generation;
    _notify();
    try {
      final next = RoomApi(uri);
      final health = await next.request('health');
      if (health['service'] != 'mubangumi-banjian' || health['protocol'] != 1) {
        throw const RoomError(400, '不是兼容的番键会服务器');
      }
      next.token = (await next.request('login', {
        'password': adminPassword,
      }))['token'];
      api = next;
      base = uri;
      remote = true;
      running = true;
      await _loadCommands();
      password = null;
      error = null;
      addresses = [uri.toString().replaceAll(RegExp(r'/$'), '')];
      event = null;
      _historySelection = null;
      await refresh();
      _beginPoll();
    } finally {
      busy = false;
      _notify();
    }
  }

  void _beginPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (timer) {
      unawaited(refresh(wait: false));
      if (!remote && timer.tick % 4 == 0) {
        unawaited(refreshAddresses().catchError((Object _) {}));
      }
    });
  }

  Future<void> refreshAddresses() async {
    if (remote || base == null) return;
    final generation = _generation;
    final found = await listRoomAddresses(base!.port);
    if (generation != _generation || _disposed) return;
    networkAddresses = found.where((v) => v.privateLan).toList();
    final next = networkAddresses.map((v) => v.address).toList();
    if (next.isEmpty) {
      next.add(base.toString().replaceAll(RegExp(r'/$'), ''));
    }
    if (addresses.isNotEmpty && !listEquals(addresses, next)) {
      networkNotice = '网络地址已变化，已更新推荐地址，请重新分享二维码。';
    }
    addresses = next;
    _notify();
  }

  Future<void> refresh({String? eventId, bool wait = true}) async {
    if (eventId != null || wait) {
      while (_polling && !_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (api == null || _polling) return;
    _polling = true;
    final generation = _generation;
    final client = api!;
    try {
      // Live vote invalidations need only the selected room. Periodic polling
      // still discovers rooms created or ended by another administrator.
      if (wait ||
          eventId != null ||
          !identical(client, _historyClient) ||
          _historyLoadedAt == null ||
          DateTime.now().difference(_historyLoadedAt!) >=
              const Duration(seconds: 4)) {
        final result = await client.request('history');
        if (generation != _generation) return;
        history = (result['events'] as List).cast<Json>();
        _historyLoadedAt = DateTime.now();
        _historyClient = client;
      }
      if (eventId != null) {
        _historySelection =
            history.where((e) => e['id'] == eventId).firstOrNull?['ended'] ==
                true
            ? eventId
            : null;
      }
      final active = history.where((e) => e['ended'] != true).firstOrNull;
      final id =
          eventId ??
          _historySelection ??
          active?['id'] ??
          event?['id'] ??
          (history.isEmpty ? null : history.first['id']);
      if (id != null) {
        final data = await client.request('state?event=$id');
        if (generation != _generation) return;
        final parsed = RoomSnapshot.fromJson(data);
        if (event?['id'] == data['id'] &&
            sameRoomEpoch(event, data) &&
            parsed.revision < _announcedRevision) {
          _refreshAfterPoll = true;
        }
        if (event?['id'] != data['id'] ||
            !sameRoomEpoch(event, data) ||
            (parsed.version >= (event?['version'] as int? ?? 0) &&
                parsed.revision >=
                    (event?['revision'] as int? ??
                        event?['version'] as int? ??
                        0))) {
          if (!sameRoomEpoch(event, data)) _announcedRevision = 0;
          event = parsed.toJson();
          client.rememberSnapshot(event!);
        }
      }
      error = null;
      _notify();
      unawaited(_watchLive());
    } catch (e) {
      if (generation != _generation) return;
      error = e.toString();
      _notify();
    } finally {
      _polling = false;
      if (_refreshAfterPoll && !_disposed && generation == _generation) {
        _refreshAfterPoll = false;
        unawaited(refresh(wait: false));
      }
    }
  }

  Future<void> command(String action, [Json extra = const {}]) async {
    if (api == null) return;
    if (_commandBusy || _pendingAdmin != null) {
      throw const RoomError(409, '上一项管理操作尚未确认，请先核对');
    }
    await _saveCommand({
      'op': newSecret(),
      'event': event?['id'],
      'version': event?['version'],
      'action': action,
      ...extra,
    });
    await retryCommand();
  }

  Future<void> retryCommand() async {
    if (_commandBusy || _pendingAdmin == null || api == null) return;
    _commandBusy = true;
    try {
      final result = await api!.request('admin', _pendingAdmin);
      await _saveCommand(null);
      // Wait for a concurrent polling request before selecting the newly created event.
      while (_polling) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await refresh(eventId: result['id']);
    } on RoomError catch (e) {
      if (e.status < 500 && e.status != 401 && e.status != 429) {
        await _saveCommand(null);
      }
      await refresh();
      rethrow;
    } finally {
      _commandBusy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    ++_generation;
    ++_liveEpoch;
    _openingSocket = false;
    liveConnected = false;
    _liveKey = null;
    unawaited(_liveSocket?.close());
    _liveSocket = null;
    _poll?.cancel();
    if (remote) {
      try {
        await api?.request('logout', {});
      } catch (_) {}
    } else {
      _control?.send('stop');
      try {
        await _stopped?.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        _isolate?.kill(priority: Isolate.immediate);
      }
      if (Platform.isAndroid) await _channel.invokeMethod<void>('stop');
    }
    _receive?.close();
    _receive = null;
    _isolate = null;
    _control = null;
    running = false;
    api = null;
    password = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(stop());
    super.dispose();
  }
}

Future<void> _hostMain(Json args) async {
  final send = args['send'] as SendPort;
  RoomStore? store;
  RoomServer? server;
  final receive = ReceivePort();
  send.send(receive.sendPort);
  try {
    store = RoomStore(args['path']);
    server = RoomServer(
      autoCacheCovers: args['autoCacheCovers'] as bool? ?? true,
      store: store,
      adminPassword: args['password'],
      assets: Map<String, List<int>>.from(args['assets']),
    );
    await server.start(port: args['port'] as int? ?? 43928);
    send.send(server.port);
    await receive.firstWhere((command) => command == 'stop');
  } catch (e) {
    send.send(e is SocketException ? '端口 43928 已被占用或没有网络权限' : '服务启动失败：$e');
  } finally {
    receive.close();
    await server?.close();
    store?.close();
  }
}
