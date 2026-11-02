import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../storage/serial_task_queue.dart';

class AuthCleanupState {
  const AuthCleanupState({
    this.apiNonce,
    this.websiteNonce,
    this.apiPending = false,
    this.websiteStorePending = false,
    this.websiteCookiesPending = false,
  });
  final String? apiNonce, websiteNonce;
  final bool apiPending, websiteStorePending, websiteCookiesPending;
  bool get websitePending => websiteStorePending || websiteCookiesPending;
  bool get pending => apiPending || websitePending;
}

/// Independent API, website-storage and browser cleanup phases. Only flags and
/// an operation identity are stored here, never credentials or participation
/// tokens. A late completion cannot unlock a newer account's logout operation.
abstract final class AuthCleanupMarker {
  static final _operations = SerialTaskQueue();
  static _CleanupBackend _backend = _FileCleanupBackend();
  static String _nonce() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  static Future<T> _run<T>(Future<T> Function(_CleanupBackend) action) {
    final backend = _backend;
    return _operations.run(() => action(backend));
  }

  static Future<AuthCleanupState> current() =>
      _run((backend) => backend.read());
  static Future<String> beginLogout() => _run((backend) async {
    final nonce = _nonce();
    await backend.write(
      AuthCleanupState(
        apiNonce: nonce,
        websiteNonce: nonce,
        apiPending: true,
        websiteStorePending: true,
        websiteCookiesPending: true,
      ),
    );
    return nonce;
  });
  static Future<String> beginWebsiteCleanup({
    bool includeStoredSession = false,
  }) => _run((backend) async {
    final previous = await backend.read();
    final nonce =
        !includeStoredSession &&
            previous.websitePending &&
            previous.websiteNonce != null
        ? previous.websiteNonce!
        : _nonce();
    await backend.write(
      AuthCleanupState(
        apiNonce: previous.apiNonce,
        websiteNonce: nonce,
        apiPending: previous.apiPending,
        websiteStorePending:
            previous.websiteStorePending || includeStoredSession,
        websiteCookiesPending: true,
      ),
    );
    return nonce;
  });
  static Future<void> completeApi(String? nonce) => _complete(nonce, api: true);
  static Future<void> completeWebsiteStore(String? nonce) =>
      _complete(nonce, store: true);
  static Future<void> completeWebsiteCookies(String? nonce) =>
      _complete(nonce, cookies: true);
  static Future<void> _complete(
    String? nonce, {
    bool api = false,
    bool store = false,
    bool cookies = false,
  }) {
    if (nonce == null) return Future.value();
    return _run((backend) async {
      final current = await backend.read();
      if ((api ? current.apiNonce : current.websiteNonce) != nonce) return;
      await backend.write(
        AuthCleanupState(
          apiNonce: current.apiNonce,
          websiteNonce: current.websiteNonce,
          apiPending: api ? false : current.apiPending,
          websiteStorePending: store ? false : current.websiteStorePending,
          websiteCookiesPending: cookies
              ? false
              : current.websiteCookiesPending,
        ),
      );
    });
  }

  @visibleForTesting
  static void useMemoryForTests() {
    _backend = _MemoryCleanupBackend();
  }

  @visibleForTesting
  static void useFileForTests(File file) {
    _backend = _FileCleanupBackend(file);
  }
}

abstract interface class _CleanupBackend {
  Future<AuthCleanupState> read();
  Future<void> write(AuthCleanupState value);
}

class _MemoryCleanupBackend implements _CleanupBackend {
  AuthCleanupState state = const AuthCleanupState();
  @override
  Future<AuthCleanupState> read() async => state;
  @override
  Future<void> write(AuthCleanupState value) async {
    state = value.pending ? value : const AuthCleanupState();
  }
}

class _FileCleanupBackend implements _CleanupBackend {
  _FileCleanupBackend([this.fileOverride]);
  final File? fileOverride;
  Future<File> _file() async =>
      fileOverride ??
      File(
        path.join(
          (await getApplicationSupportDirectory()).path,
          'auth',
          'cleanup-state.json',
        ),
      );
  static const corrupt = AuthCleanupState(
    apiNonce: 'corrupt',
    websiteNonce: 'corrupt',
    apiPending: true,
    websiteStorePending: true,
    websiteCookiesPending: true,
  );
  @override
  Future<AuthCleanupState> read() async {
    final file = await _file();
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return const AuthCleanupState();
    if (type != FileSystemEntityType.file) throw StateError('无法读取本机登录清理状态');
    if (await file.length() > 4096) return corrupt;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map ||
          data['api'] is! bool ||
          data['website_store'] is! bool ||
          data['website_cookies'] is! bool) {
        return corrupt;
      }
      if ((data['api_nonce'] != null && data['api_nonce'] is! String) ||
          (data['website_nonce'] != null && data['website_nonce'] is! String)) {
        return corrupt;
      }
      if (data['api'] == true &&
          (data['api_nonce'] is! String ||
              (data['api_nonce'] as String).isEmpty)) {
        return corrupt;
      }
      if ((data['website_store'] == true || data['website_cookies'] == true) &&
          (data['website_nonce'] is! String ||
              (data['website_nonce'] as String).isEmpty)) {
        return corrupt;
      }
      return AuthCleanupState(
        apiNonce: data['api_nonce'] as String?,
        websiteNonce: data['website_nonce'] as String?,
        apiPending: data['api'] as bool,
        websiteStorePending: data['website_store'] as bool,
        websiteCookiesPending: data['website_cookies'] as bool,
      );
    } on FormatException {
      return corrupt;
    }
  }

  @override
  Future<void> write(AuthCleanupState value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    if (!value.pending) {
      if (await file.exists()) await file.delete();
      return;
    }
    final temporary = File(
      '${file.path}.$pid-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.create(exclusive: true);
      await temporary.writeAsString(
        jsonEncode({
          'api_nonce': value.apiNonce,
          'website_nonce': value.websiteNonce,
          'api': value.apiPending,
          'website_store': value.websiteStorePending,
          'website_cookies': value.websiteCookiesPending,
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
