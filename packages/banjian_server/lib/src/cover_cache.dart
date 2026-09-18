import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'protocol.dart';
import 'store.dart';

class RoomCoverImage {
  const RoomCoverImage(this.bytes, this.mime);
  final List<int> bytes;
  final String mime;
}

typedef RoomCoverLoader = Future<RoomCoverImage> Function(Uri uri);

/// Only selected Bangumi artwork is fetched; never arbitrary participant URLs.
class RoomCoverCache {
  RoomCoverCache(this.store, {required this.lookup, RoomCoverLoader? loader})
    : loader = loader ?? download;
  final RoomStore store;
  final Future<String?> Function(int id) lookup;
  final RoomCoverLoader loader;
  final _known = <int, String>{};
  bool closed = false;
  bool contains(String key) =>
      key.isNotEmpty &&
      store.db.select('SELECT 1 FROM covers WHERE id=?', [key]).isNotEmpty;
  Future<String> ensure(Json subject) async {
    if (closed) throw const RoomError(503, '服务已停止');
    final id = subject['id'] as int;
    final current = subject['cover'] as String? ?? '';
    if (contains(current)) return current;
    final known = _known[id];
    if (known != null && contains(known)) return known;
    var source = roomCoverUri(subject['coverSource'] as String? ?? '');
    source ??= roomCoverUri(await lookup(id) ?? '');
    if (closed) throw const RoomError(503, '服务已停止');
    if (source == null) throw const RoomError(502, '条目暂未提供可用封面');
    final key = digest(source.toString());
    if (!contains(key)) {
      final image = await loader(source);
      if (closed) throw const RoomError(503, '服务已停止');
      if (image.bytes.isEmpty ||
          image.bytes.length > 2 * 1024 * 1024 ||
          !validCoverImage(image))
        throw const RoomError(502, '封面图片格式无效');
      store.db.execute('INSERT OR REPLACE INTO covers VALUES(?,?,?)', [
        key,
        image.mime,
        Uint8List.fromList(image.bytes),
      ]);
    }
    _known[id] = key;
    return key;
  }

  static bool validCoverImage(RoomCoverImage image) {
    final b = image.bytes;
    return (image.mime == 'image/jpeg' &&
            b.length >= 3 &&
            b[0] == 255 &&
            b[1] == 216 &&
            b[2] == 255) ||
        (image.mime == 'image/png' &&
            b.length >= 8 &&
            b.take(8).join(',') == '137,80,78,71,13,10,26,10') ||
        (image.mime == 'image/webp' &&
            b.length >= 12 &&
            String.fromCharCodes(b.take(4)) == 'RIFF' &&
            String.fromCharCodes(b.skip(8).take(4)) == 'WEBP');
  }

  static Future<RoomCoverImage> download(Uri uri) async {
    if (roomCoverUri(uri.toString()) == null)
      throw const RoomError(400, '封面来源无效');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      request.headers.set('User-Agent', 'MuBangumi-Banjian/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) throw const RoomError(502, '封面下载失败');
      final mime = response.headers.contentType?.mimeType ?? '';
      if (!['image/jpeg', 'image/png', 'image/webp'].contains(mime))
        throw const RoomError(502, '封面返回的不是图片');
      final bytes = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.add(chunk);
        if (bytes.length > 2 * 1024 * 1024)
          throw const RoomError(502, '封面文件过大');
      }
      return RoomCoverImage(bytes.takeBytes(), mime);
    } finally {
      client.close(force: true);
    }
  }
}
