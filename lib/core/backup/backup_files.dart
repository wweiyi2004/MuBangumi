import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_archive.dart';

class PickedBackup {
  const PickedBackup(this.name, this.archive);
  final String name;
  final BackupArchive archive;
}

abstract class BackupFiles {
  Future<PickedBackup?> pick();
  Future<String?> save(BackupArchive archive);
  Future<void> share(BackupArchive archive, {required Rect origin});
}

class PlatformBackupFiles implements BackupFiles {
  PlatformBackupFiles({this.picker});
  final FilePicker? picker;
  FilePicker get _platform => picker ?? FilePicker.platform;

  @override
  Future<PickedBackup?> pick() async {
    final result = await _platform.pickFiles(
      dialogTitle: '选择 MuBangumi 备份',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
      withReadStream: true,
      lockParentWindow: true,
    );
    if (result == null) return null;
    if (result.files.length != 1) throw const BackupException('请选择一个备份文件');
    final file = result.files.single;
    final bytes = await readBackupFile(file);
    final archive = await compute(BackupArchive.decode, bytes);
    return PickedBackup(file.name, archive);
  }

  @override
  Future<String?> save(BackupArchive archive) async => _platform.saveFile(
    dialogTitle: '保存 MuBangumi 备份',
    fileName: backupFileName(archive),
    type: FileType.custom,
    allowedExtensions: ['json'],
    bytes: await compute(_encodeBackup, archive),
    lockParentWindow: true,
  );

  @override
  Future<void> share(BackupArchive archive, {required Rect origin}) async {
    final bytes = await compute(_encodeBackup, archive);
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'application/json')],
      fileNameOverrides: [backupFileName(archive)],
      subject: 'MuBangumi 本地备份',
      sharePositionOrigin: origin,
    );
  }
}

Uint8List _encodeBackup(BackupArchive archive) => archive.encode();
String backupFileName(BackupArchive archive) =>
    'MuBangumi-${archive.owner.id}-${archive.createdAt.toUtc().toIso8601String().replaceAll(':', '-')}.json';

/// A picker filter is only a convenience. Bound the actual byte stream even if
/// a document provider supplies an inaccurate size, then validate the format.
Future<Uint8List> readBackupFile(PlatformFile file) async {
  if (file.size < 0 || file.size > BackupArchive.maxBytes) {
    throw const BackupException('备份超过 16 MB 限制');
  }
  final Stream<List<int>> stream;
  if (file.readStream != null) {
    stream = file.readStream!;
  } else if (file.bytes != null) {
    stream = Stream.value(file.bytes!);
  } else if (file.path != null) {
    stream = File(file.path!).openRead();
  } else {
    throw const BackupException('无法读取所选文件，请重新选择');
  }
  final bytes = BytesBuilder();
  try {
    await for (final chunk in stream.timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > BackupArchive.maxBytes) {
        throw const BackupException('备份超过 16 MB 限制');
      }
      bytes.add(chunk);
    }
  } on TimeoutException {
    throw const BackupException('读取备份超时，请检查文件是否已下载到本机');
  }
  if (file.size > 0 && bytes.length != file.size) {
    throw const BackupException('文件长度与选择时不同，请重新选择');
  }
  if (bytes.isEmpty) throw const BackupException('所选文件为空');
  return bytes.takeBytes();
}
