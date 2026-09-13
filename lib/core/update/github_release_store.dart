import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers a GitHub release tag the user chose to skip.
class GithubReleaseSkipStore {
  GithubReleaseSkipStore({
    FlutterSecureStorage? storage,
    Map<String, String>? memory,
  }) : _storage = memory == null
           ? storage ?? const FlutterSecureStorage()
           : null,
       _memory = memory;

  static const key = 'skipped_github_release_tag';

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _memory;

  Future<String?> readSkippedTag() async {
    if (_memory != null) return _memory[key];
    return _storage!.read(key: key);
  }

  Future<void> skipTag(String tag) async {
    if (_memory != null) {
      _memory[key] = tag;
      return;
    }
    await _storage!.write(key: key, value: tag);
  }

  Future<DateTime?> remindAfter(String tag) async {
    final name = 'update_remind_after:$tag';
    final value = _memory != null
        ? _memory[name]
        : await _storage!.read(key: name);
    return DateTime.tryParse(value ?? '');
  }

  Future<void> postpone(String tag, DateTime until) async {
    final name = 'update_remind_after:$tag';
    final value = until.toUtc().toIso8601String();
    if (_memory != null) {
      _memory[name] = value;
      return;
    }
    await _storage!.write(key: name, value: value);
  }
}
