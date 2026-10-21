import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:mubangumi/core/storage/serial_task_queue.dart';
import 'package:sqflite/sqflite.dart';

/// UI fixtures exercise the real encoders and domain parsers without doing
/// database I/O inside a widget's fake async clock. Storage tests inject their
/// own real database explicitly.
class MemoryCommunityCache extends CommunityCache {
  MemoryCommunityCache() : super.test(connection: _UnusedDatabase());
  _CacheValues _values = _CacheValues();
  void reset() {
    _values = _CacheValues();
  }

  @override
  Future<T?> readDecoded<T>(String key, T? Function(String) decode) async {
    final values = _values;
    await values.writes.done;
    final value = values.payloads[key];
    if (value == null) return null;
    try {
      return decode(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> updateEncoded(
    String key,
    Future<String?> Function(String?) update, {
    bool readExisting = false,
    bool accountScoped = false,
  }) {
    final values = _values;
    return values.writes.run(() async {
      final value = await update(readExisting ? values.payloads[key] : null);
      if (value == null) {
        values.payloads.remove(key);
        values.scoped.remove(key);
        return;
      }
      values.payloads[key] = value;
      if (accountScoped) {
        values.scoped.add(key);
      } else {
        values.scoped.remove(key);
      }
    });
  }

  @override
  Future<void> remove(String key) {
    final values = _values;
    return values.writes.run(() async {
      values.payloads.remove(key);
      values.scoped.remove(key);
    });
  }

  @override
  Future<void> removePrefix(String prefix) {
    final values = _values;
    return values.writes.run(() async {
      values.payloads.removeWhere((key, _) => key.startsWith(prefix));
      values.scoped.removeWhere((key) => key.startsWith(prefix));
    });
  }

  @override
  Future<void> clearAccountData() {
    final values = _values;
    return values.writes.run(() async {
      for (final key in values.scoped) {
        values.payloads.remove(key);
      }
      values.scoped.clear();
    });
  }

  @override
  Future<void> prune() async {}
}

class _CacheValues {
  final payloads = <String, String>{};
  final scoped = <String>{};
  final writes = SerialTaskQueue();
}

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Memory cache requested an unexpected database operation',
  );
}
