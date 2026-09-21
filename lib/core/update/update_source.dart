import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum UpdateSource { auto, domestic, github }

/// Override at build time when distributing a fork or disabling the mirror.
const giteeRepository = String.fromEnvironment(
  'GITEE_REPOSITORY',
  defaultValue: 'wweiyi/mu-bangumi',
);

bool validGiteeRepository(String value) =>
    RegExp(r'^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$').hasMatch(value) &&
    !value.split('/').any((s) => s == '.' || s == '..');

bool trustedGiteeAssetUrl(String url, String repository) {
  if (!validGiteeRepository(repository)) return false;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'gitee.com' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  final prefix = '/api/v5/repos/$repository/releases/';
  final parts = uri.pathSegments;
  final releasePath =
      parts.length == 6 &&
      parts.take(4).join('/') == '$repository/releases/download' &&
      RegExp(r'^v?\d+(?:\.\d+)*(?:\+\d+)?$').hasMatch(parts[4]) &&
      RegExp(r'^[a-zA-Z0-9._+\-]+$').hasMatch(parts[5]);
  return releasePath ||
      (uri.path.startsWith(prefix) &&
          RegExp(
            r'^\d+/attach_files/\d+/download$',
          ).hasMatch(uri.path.substring(prefix.length)));
}

class UpdateSourceStore {
  const UpdateSourceStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'update_download_source';

  Future<UpdateSource> read() async {
    try {
      final value = await _storage.read(key: _key);
      return UpdateSource.values.firstWhere(
        (source) => source.name == value,
        orElse: () => UpdateSource.auto,
      );
    } catch (_) {
      return UpdateSource.auto;
    }
  }

  Future<void> write(UpdateSource source) =>
      _storage.write(key: _key, value: source.name);
}
