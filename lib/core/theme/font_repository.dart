import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/app_font.dart';

abstract interface class FontRepository {
  Future<String?> readSelection();
  Future<void> saveSelection(String? id);
  Future<Set<String>> installed();
  Future<void> activate(AppFont font);
  Future<void> download(
    AppFont font,
    CancelToken cancel,
    void Function(double) progress,
  );
  Future<void> remove(AppFont font);
}

abstract interface class ImportableFontRepository implements FontRepository {
  Future<List<AppFont>> importedFonts();
  Future<AppFont> importFont(String name, Uint8List bytes);
}

/// Validate SFNT table boundaries before handing an imported font to the engine.
bool validImportedFont(Uint8List bytes) {
  if (bytes.length < 28 || bytes.length > 64 * 1024 * 1024) return false;
  final data = ByteData.sublistView(bytes);
  bool sfnt(int start) {
    if (start < 0 || start + 12 > bytes.length) return false;
    final magic = data.getUint32(start);
    if (magic != 0x00010000 && magic != 0x4f54544f) return false;
    final count = data.getUint16(start + 4);
    if (count == 0 || count > 256 || start + 12 + count * 16 > bytes.length) {
      return false;
    }
    final tags = <int>{};
    for (var i = 0; i < count; i++) {
      final row = start + 12 + i * 16;
      tags.add(data.getUint32(row));
      final offset = data.getUint32(row + 8), size = data.getUint32(row + 12);
      if (offset + size > bytes.length) return false;
    }
    return tags.contains(0x636d6170) &&
        tags.contains(0x68656164) &&
        tags.contains(0x6e616d65);
  }

  if (data.getUint32(0) != 0x74746366) return sfnt(0);
  final count = data.getUint32(8);
  if (count == 0 || count > 64 || 12 + count * 4 > bytes.length) return false;
  for (var i = 0; i < count; i++) {
    if (!sfnt(data.getUint32(12 + i * 4))) return false;
  }
  return true;
}

bool validFontDownload((AppFont, Uint8List) input) {
  final (font, bytes) = input;
  if (bytes.length != font.bytes || bytes.length < 12) return false;
  final header = ByteData.sublistView(bytes).getUint32(0);
  if (font.imported
      ? !validImportedFont(bytes)
      : (header != 0x00010000 && header != 0x4f54544f)) {
    return false;
  }
  final Digest digest;
  if (font.gitBlob) {
    final result = _FontDigestSink();
    final sink = sha1.startChunkedConversion(result);
    sink.add(utf8.encode('blob ${bytes.length}\u0000'));
    sink.add(bytes);
    sink.close();
    digest = result.value;
  } else {
    digest = sha256.convert(bytes);
  }
  return digest.toString() == font.digest;
}

class _FontDigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest digest) => value = digest;
  @override
  void close() {}
}

class LocalFontRepository implements ImportableFontRepository {
  LocalFontRepository({
    Dio? dio,
    FlutterSecureStorage? storage,
    Future<Directory> Function()? directory,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(minutes: 2),
             ),
           ),
       _storage = storage ?? const FlutterSecureStorage(),
       _directory = directory ?? getApplicationSupportDirectory;
  final Dio
  _dio; // Public font downloads never receive API or website credentials.
  final FlutterSecureStorage _storage;
  final Future<Directory> Function() _directory;
  final _loaded = <String>{};
  static const _key = 'appearance_font';
  Future<File> _catalogFile() async =>
      File('${(await _directory()).path}/fonts/imported.json');
  @override
  Future<List<AppFont>> importedFonts() async {
    final file = await _catalogFile();
    if (!await file.exists()) return [];
    final raw = jsonDecode(await file.readAsString()) as List;
    return [
      for (final row in raw)
        if (row is Map &&
            RegExp(r'^imported-[a-f0-9]{64}$').hasMatch('${row['id']}') &&
            row['id'] == 'imported-${row['digest']}' &&
            row['bytes'] is int &&
            (row['bytes'] as int) > 0 &&
            (row['bytes'] as int) <= 64 * 1024 * 1024)
          AppFont(
            id: row['id'],
            name: '${row['name']}'.substring(
              0,
              '${row['name']}'.length.clamp(0, 64),
            ),
            family: 'Mu${row['id']}',
            description: '本地导入',
            url: '',
            bytes: row['bytes'],
            digest: row['digest'],
            licenseAsset: '',
            imported: true,
          ),
    ];
  }

  Future<void> _saveCatalog(List<AppFont> fonts) async {
    final file = await _catalogFile();
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsString(
      jsonEncode([
        for (final f in fonts)
          {'id': f.id, 'name': f.name, 'bytes': f.bytes, 'digest': f.digest},
      ]),
      flush: true,
    );
    await part.rename(file.path);
  }

  @override
  Future<AppFont> importFont(String name, Uint8List bytes) async {
    if (!await compute(validImportedFont, bytes)) {
      throw const FormatException('请选择有效的 TTF、OTF 或 TTC 字库，大小不超过 64 MB');
    }
    final digest = sha256.convert(bytes).toString();
    final id = 'imported-$digest';
    final fonts = await importedFonts();
    final existing = fonts.where((f) => f.id == id).firstOrNull;
    final font =
        existing ??
        AppFont(
          id: id,
          name: name.trim().isEmpty
              ? '导入字体'
              : name.trim().substring(0, name.trim().length.clamp(0, 64)),
          family: 'Mu$id',
          description: '本地导入',
          url: '',
          bytes: bytes.length,
          digest: digest,
          licenseAsset: '',
          imported: true,
        );
    final file = await _file(font);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    await _saveCatalog([...fonts.where((f) => f.id != id), font]);
    return font;
  }

  Future<File> _file(AppFont font) async {
    final root = await _directory();
    return File('${root.path}/fonts/${font.id}.ttf');
  }

  @override
  Future<String?> readSelection() => _storage.read(key: _key);
  @override
  Future<void> saveSelection(String? id) => id == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: id);
  @override
  Future<Set<String>> installed() async {
    final result = <String>{};
    for (final font in [...downloadableFonts, ...await importedFonts()]) {
      if (await (await _file(font)).exists()) result.add(font.id);
    }
    return result;
  }

  @override
  Future<void> activate(AppFont font) async {
    if (_loaded.contains(font.id)) return;
    final bytes = await (await _file(font)).readAsBytes();
    if (!await compute(validFontDownload, (font, bytes))) {
      throw const FormatException('字体文件校验失败，请移除后重新下载');
    }
    await (FontLoader(
      font.family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    _loaded.add(font.id);
  }

  @override
  Future<void> download(
    AppFont font,
    CancelToken cancel,
    void Function(double) progress,
  ) async {
    final response = await _dio.get<List<int>>(
      font.url,
      cancelToken: cancel,
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: (received, total) =>
          progress((received / font.bytes).clamp(0.0, 1.0)),
    );
    if (cancel.isCancelled) throw cancel.cancelError ?? StateError('已取消下载');
    final bytes = Uint8List.fromList(response.data ?? const []);
    if (!await compute(validFontDownload, (font, bytes))) {
      throw const FormatException('字体下载不完整或校验失败，请重试');
    }
    if (cancel.isCancelled) throw cancel.cancelError ?? StateError('已取消下载');
    final file = await _file(font);
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.part');
    try {
      await pending.writeAsBytes(bytes, flush: true);
      if (cancel.isCancelled) throw cancel.cancelError ?? StateError('已取消下载');
      await pending.rename(file.path);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }

  @override
  Future<void> remove(AppFont font) async {
    final file = await _file(font);
    if (await file.exists()) await file.delete();
    if (font.imported) {
      await _saveCatalog(
        (await importedFonts()).where((f) => f.id != font.id).toList(),
      );
    }
    _loaded.remove(font.id);
  }
}
