import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/backup/backup_plan.dart';

import 'support/backup_fixtures.dart';

Uint8List rewrite(
  BackupArchive archive,
  void Function(Map<String, dynamic>) edit, {
  bool sign = true,
}) {
  final root =
      jsonDecode(utf8.decode(archive.encode())) as Map<String, dynamic>;
  edit(root);
  if (sign) root['checksum'] = backupDigest({...root}..remove('checksum'));
  return Uint8List.fromList(utf8.encode(jsonEncode(root)));
}

void main() {
  final archive = BackupArchive.create(
    owner: backupOwner,
    data: {
      BackupCategory.pins: [backupPin(123, 0)],
    },
    createdAt: DateTime.utc(2026, 9, 8),
  );
  test('UTF8 canonical integrity survives roundtrip and map order changes', () {
    final data = BackupArchive.create(
      owner: backupOwner,
      data: {
        BackupCategory.people: [backupPerson('person', ' 🌸\n“引号” \\ 路径 [文字]')],
      },
    );
    expect(BackupArchive.decode(data.encode()).data, data.data);
    final reordered = rewrite(data, (root) {
      root['owner'] = {'username': 'alice', 'id': 11};
    }, sign: false);
    expect(BackupArchive.decode(reordered).checksum, data.checksum);
    expect(
      () => data.data[BackupCategory.people]!.single['note'] = '改写',
      throwsUnsupportedError,
    );
  });
  final badEdits = <String, void Function(Map<String, dynamic>)>{
    'unknown root field': (r) => r['token'] = 'credential',
    'unknown category': (r) => r['data']['token'] = [],
    'unknown version': (r) => r['version'] = 2,
    'fractional version': (r) => r['version'] = 1.0,
    'missing owner': (r) => r.remove('owner'),
    'negative owner': (r) => r['owner']['id'] = -1,
    'blank username': (r) => r['owner']['username'] = ' ',
    'bad time': (r) => r['created_at'] = '2026-09-08',
    'normalized invalid date': (r) =>
        r['created_at'] = '2026-02-31T00:00:00.000Z',
    'extra row field': (r) => r['data']['pins'][0]['cookie'] = 'cookie',
    'invalid positive ID': (r) => r['data']['pins'][0]['subject_id'] = 0,
    'fractional ID': (r) => r['data']['pins'][0]['subject_id'] = 12.0,
    'position gap': (r) => r['data']['pins'][0]['position'] = 1,
    'duplicate row': (r) => r['data']['pins'].add(backupPin(123, 1)),
    'empty categories': (r) => r['data'] = {},
  };
  for (final entry in badEdits.entries) {
    test('rejects ${entry.key} before import', () {
      expect(
        () => BackupArchive.decode(rewrite(archive, entry.value)),
        throwsA(isA<BackupException>()),
      );
    });
  }
  test('rejects damaged checksum, malformed UTF8, deep or oversized files', () {
    expect(
      () => BackupArchive.decode(
        rewrite(archive, (r) => r['owner']['id'] = 22, sign: false),
      ),
      throwsA(isA<BackupException>()),
    );
    for (final bytes in [
      Uint8List.fromList([0xff, 0xfe]),
      Uint8List(BackupArchive.maxBytes + 1),
      Uint8List.fromList(utf8.encode('${'[' * 1000}0${']' * 1000}')),
    ]) {
      expect(
        () => BackupArchive.decode(bytes),
        throwsA(isA<BackupException>()),
      );
    }
  });
  test(
    'combined plans preserve local order and limit search history honestly',
    () {
      final incoming = BackupArchive.create(
        owner: backupOwner,
        data: {
          BackupCategory.pins: [
            backupPin(456, 0),
            backupPin(123, 1),
            backupPin(789, 2),
          ],
          BackupCategory.browsing: [
            for (var i = 0; i < 12; i++) backupSearch('import $i', i),
          ],
        },
      );
      final local = {
        BackupCategory.pins: [backupPin(123, 0), backupPin(456, 1)],
        BackupCategory.browsing: [
          for (var i = 0; i < 11; i++) backupSearch('local $i', i),
        ],
      };
      final selected = incoming.data.keys.toSet();
      final preview = BackupPreview.create(
        incoming,
        local,
        selected,
        BackupImportMode.merge,
      );
      final result = mergeBackupRows(
        local,
        incoming.data,
        selected,
        BackupImportMode.merge,
      );
      expect(result[BackupCategory.pins], [
        backupPin(123, 0),
        backupPin(456, 1),
        backupPin(789, 2),
      ]);
      expect(preview.skippedSearches, 11);
      expect(preview.count(BackupCategory.browsing, BackupChangeKind.added), 1);
      expect(
        preview.count(BackupCategory.browsing, BackupChangeKind.limited),
        11,
      );
      expect(
        BackupPreview.create(
          incoming,
          result,
          selected,
          BackupImportMode.merge,
        ).hasChanges,
        false,
      );
    },
  );
  test(
    'same quarter merge preserves existing fields and appends new shows by day',
    () {
      final local = {
        BackupCategory.schedules: [
          {
            'season': backupSeason.toJson(),
            'items': [backupItem.toJson()],
          },
        ],
      };
      final incoming = {
        BackupCategory.schedules: [
          {
            'season': backupSeason.toJson(),
            'items': [
              backupItem.copyWith(note: 'older').toJson(),
              backupItem.copyWith(subjectId: 456, sortOrder: 0).toJson(),
            ],
          },
        ],
      };
      final result = mergeBackupRows(local, incoming, {
        BackupCategory.schedules,
      }, BackupImportMode.merge);
      final items = result[BackupCategory.schedules]!.single['items'] as List;
      expect(items.first, backupItem.toJson());
      expect(items.last['sortOrder'], 2);
    },
  );
  test('replace clears missing rows only in selected categories', () {
    final incoming = BackupArchive.create(
      owner: backupOwner,
      data: {BackupCategory.pins: []},
    );
    final local = {
      BackupCategory.pins: [backupPin(123, 0)],
      BackupCategory.people: [backupPerson('person', 'keep')],
    };
    final preview = BackupPreview.create(incoming, local, {
      BackupCategory.pins,
    }, BackupImportMode.replace);
    expect(preview.count(BackupCategory.pins, BackupChangeKind.removed), 1);
    expect(
      mergeBackupRows(local, incoming.data, preview.categories, preview.mode),
      {BackupCategory.pins: []},
    );
  });
}
