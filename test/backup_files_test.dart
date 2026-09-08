import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/backup/backup_files.dart';

import 'support/backup_fixtures.dart';

void main() {
  final archive = BackupArchive.create(
    owner: backupOwner,
    data: {
      BackupCategory.pins: [backupPin(123, 0)],
    },
    createdAt: DateTime.utc(2026, 9, 8),
  );
  test(
    'stream import is bounded, preserves bytes and validates off the UI isolate',
    () async {
      final bytes = archive.encode();
      final picker = _Picker()
        ..result = FilePickerResult([
          PlatformFile(
            name: 'backup.json',
            size: bytes.length,
            readStream: Stream.fromIterable([
              bytes.sublist(0, 9),
              bytes.sublist(9),
            ]),
          ),
        ]);
      final picked = await PlatformBackupFiles(picker: picker).pick();
      expect(picked!.name, 'backup.json');
      expect(picked.archive.checksum, archive.checksum);
      expect(picker.streamRequested, true);
      expect(picker.dataRequested, false);
    },
  );
  test('cancelling the dialog neither reads nor creates a backup', () async {
    final files = PlatformBackupFiles(picker: _Picker());
    expect(await files.pick(), isNull);
    expect(await files.save(archive), isNull);
  });
  test('saving passes complete bytes to the native picker', () async {
    final picker = _Picker()..destination = 'selected.json';
    expect(
      await PlatformBackupFiles(picker: picker).save(archive),
      'selected.json',
    );
    expect(BackupArchive.decode(picker.saved!).checksum, archive.checksum);
    expect(picker.filename, 'MuBangumi-11-2026-09-08T00-00-00.000Z.json');
  });
  test('native save failure is propagated without a success result', () async {
    final picker = _Picker()..failSave = true;
    await expectLater(
      PlatformBackupFiles(picker: picker).save(archive),
      throwsA(isA<FileSystemException>()),
    );
  });
  test(
    'oversized metadata is refused before opening the supplied stream',
    () async {
      var listened = false;
      final stream = StreamController<List<int>>(
        onListen: () {
          listened = true;
        },
      );
      await expectLater(
        readBackupFile(
          PlatformFile(
            name: 'large.json',
            size: BackupArchive.maxBytes + 1,
            readStream: stream.stream,
          ),
        ),
        throwsA(isA<BackupException>()),
      );
      expect(listened, false);
      unawaited(stream.close());
    },
  );
  test(
    'a misleading file size cannot bypass the stream limit and reading cancels',
    () async {
      var cancelled = false;
      late StreamController<List<int>> stream;
      stream = StreamController<List<int>>(
        onListen: () {
          stream.add(Uint8List(BackupArchive.maxBytes));
          stream.add([1]);
        },
        onCancel: () {
          cancelled = true;
        },
      );
      await expectLater(
        readBackupFile(
          PlatformFile(name: 'large.json', size: 1, readStream: stream.stream),
        ),
        throwsA(isA<BackupException>()),
      );
      expect(cancelled, true);
      await stream.close();
    },
  );
  test('empty, truncated and malformed selected files fail', () async {
    await expectLater(
      readBackupFile(
        PlatformFile(name: 'empty.json', size: 0, bytes: Uint8List(0)),
      ),
      throwsA(isA<BackupException>()),
    );
    await expectLater(
      readBackupFile(
        PlatformFile(name: 'truncated.json', size: 10, bytes: Uint8List(3)),
      ),
      throwsA(isA<BackupException>()),
    );
    final picker = _Picker()
      ..result = FilePickerResult([
        PlatformFile(
          name: 'fake.json',
          size: 2,
          bytes: Uint8List.fromList([0xff, 0xff]),
        ),
      ]);
    await expectLater(
      PlatformBackupFiles(picker: picker).pick(),
      throwsA(isA<BackupException>()),
    );
  });
  test('path fallback reads only the selected local file', () async {
    final dir = await Directory.systemTemp.createTemp('mubangumi-file-read-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File(
      '${dir.path}/backup.json',
    ).writeAsBytes(archive.encode());
    final bytes = await readBackupFile(
      PlatformFile(
        name: 'backup.json',
        path: file.path,
        size: await file.length(),
      ),
    );
    expect(BackupArchive.decode(bytes).checksum, archive.checksum);
  });
}

class _Picker extends FilePicker {
  FilePickerResult? result;
  String? destination, filename;
  Uint8List? saved;
  bool streamRequested = false, dataRequested = true, failSave = false;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    streamRequested = withReadStream;
    dataRequested = withData;
    return result;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    if (failSave) throw const FileSystemException('disk full');
    saved = bytes;
    filename = fileName;
    return destination;
  }
}
