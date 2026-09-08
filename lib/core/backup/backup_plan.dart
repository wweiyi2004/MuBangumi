import 'backup_archive.dart';

enum BackupChangeKind { added, kept, replaced, removed, merged, limited }

class BackupChange {
  const BackupChange(this.category, this.key, this.label, this.kind);
  final BackupCategory category;
  final String key, label;
  final BackupChangeKind kind;
}

class BackupPreview {
  BackupPreview._({
    required this.archive,
    required this.mode,
    required this.categories,
    required this.beforeDigest,
    required this.resultDigest,
    required this.changes,
    required this.skippedSearches,
  });
  final BackupArchive archive;
  final BackupImportMode mode;
  final Set<BackupCategory> categories;
  final String beforeDigest, resultDigest;
  final List<BackupChange> changes;
  final int skippedSearches;
  int count(BackupCategory category, BackupChangeKind kind) => changes
      .where((change) => change.category == category && change.kind == kind)
      .length;
  bool get hasChanges => beforeDigest != resultDigest;

  factory BackupPreview.create(
    BackupArchive archive,
    BackupRows local,
    Set<BackupCategory> categories,
    BackupImportMode mode,
  ) {
    if (categories.isEmpty ||
        !archive.data.keys.toSet().containsAll(categories)) {
      throw const BackupException('请选择备份中包含的数据类别');
    }
    final changes = <BackupChange>[];
    final result = mergeBackupRows(
      local,
      archive.data,
      categories,
      mode,
      changes: changes,
    );
    BackupArchive.create(owner: archive.owner, data: result);
    final mergedHistory =
        result[BackupCategory.browsing]
            ?.where((row) => row['kind'] == 'search')
            .length ??
        0;
    final allSearches = {
      ..._rowsByKey(
        BackupCategory.browsing,
        local[BackupCategory.browsing] ?? [],
      ),
      ..._rowsByKey(
        BackupCategory.browsing,
        archive.data[BackupCategory.browsing] ?? [],
      ),
    }.values.where((row) => row['kind'] == 'search').length;
    return BackupPreview._(
      archive: archive,
      mode: mode,
      categories: Set.unmodifiable(categories),
      beforeDigest: backupRowsDigest(local, categories),
      resultDigest: backupRowsDigest(result, categories),
      changes: List.unmodifiable(changes),
      skippedSearches:
          mode == BackupImportMode.merge &&
              categories.contains(BackupCategory.browsing)
          ? (allSearches - mergedHistory).clamp(0, 50000)
          : 0,
    );
  }
}

String backupRowsDigest(BackupRows rows, Set<BackupCategory> categories) =>
    backupDigest({
      for (final category in categories)
        category.name: (rows[category] ?? []).toList()
          ..sort(
            (a, b) =>
                backupRowKey(category, a).compareTo(backupRowKey(category, b)),
          ),
    });

Map<String, Map<String, dynamic>> _rowsByKey(
  BackupCategory category,
  List<Map<String, dynamic>> rows,
) => {for (final row in rows) backupRowKey(category, row): row};

BackupRows mergeBackupRows(
  BackupRows local,
  BackupRows incoming,
  Set<BackupCategory> categories,
  BackupImportMode mode, {
  List<BackupChange>? changes,
}) {
  final result = <BackupCategory, List<Map<String, dynamic>>>{};
  for (final category in categories) {
    final current = _rowsByKey(category, local[category] ?? []);
    final source = _rowsByKey(category, incoming[category] ?? []);
    final merged = mode == BackupImportMode.merge
        ? {...current}
        : <String, Map<String, dynamic>>{};
    for (final entry in source.entries) {
      final old = current[entry.key];
      if (old == null) {
        merged[entry.key] = entry.value;
        changes?.add(
          BackupChange(
            category,
            entry.key,
            backupRowLabel(category, entry.value),
            BackupChangeKind.added,
          ),
        );
      } else if (canonicalBackupJson(old) == canonicalBackupJson(entry.value)) {
        merged[entry.key] = old;
      } else if (mode == BackupImportMode.replace) {
        merged[entry.key] = entry.value;
        changes?.add(
          BackupChange(
            category,
            entry.key,
            backupRowLabel(category, entry.value),
            BackupChangeKind.replaced,
          ),
        );
      } else if (category == BackupCategory.schedules) {
        final season = _mergeSeason(old, entry.value);
        merged[entry.key] = season;
        changes?.add(
          BackupChange(
            category,
            entry.key,
            backupRowLabel(category, season),
            canonicalBackupJson(season) == canonicalBackupJson(old)
                ? BackupChangeKind.kept
                : BackupChangeKind.merged,
          ),
        );
      } else {
        changes?.add(
          BackupChange(
            category,
            entry.key,
            backupRowLabel(category, old),
            BackupChangeKind.kept,
          ),
        );
      }
    }
    if (mode == BackupImportMode.replace) {
      for (final entry in current.entries.where(
        (entry) => !source.containsKey(entry.key),
      )) {
        changes?.add(
          BackupChange(
            category,
            entry.key,
            backupRowLabel(category, entry.value),
            BackupChangeKind.removed,
          ),
        );
      }
    }
    var rows = merged.values.toList();
    final groups = switch (category) {
      BackupCategory.pins || BackupCategory.privateDrafts => <String?>[null],
      BackupCategory.rss => <String?>['source', 'binding'],
      BackupCategory.browsing => <String?>['search'],
      _ => <String?>[],
    };
    for (final kind in groups) {
      bool ordered(Map<String, dynamic> row) =>
          kind == null || row['kind'] == kind;
      final preferred =
          (mode == BackupImportMode.merge ? current.values : source.values)
              .where(ordered)
              .toList()
            ..sort(
              (a, b) => (a['position'] as int).compareTo(b['position'] as int),
            );
      final preferredKeys = preferred
          .map((row) => backupRowKey(category, row))
          .toSet();
      final remaining =
          source.values
              .where(
                (row) =>
                    ordered(row) &&
                    !preferredKeys.contains(backupRowKey(category, row)),
              )
              .toList()
            ..sort(
              (a, b) => (a['position'] as int).compareTo(b['position'] as int),
            );
      final orderedRows = [...preferred, ...remaining];
      final limit = category == BackupCategory.browsing
          ? 12
          : orderedRows.length;
      rows = [
        for (final row in rows)
          if (!ordered(row)) row,
        for (var i = 0; i < orderedRows.length && i < limit; i++)
          {...orderedRows[i], 'position': i},
      ];
    }
    if (changes != null) {
      final appliedKeys = rows
          .map((row) => backupRowKey(category, row))
          .toSet();
      for (var i = 0; i < changes.length; i++) {
        final change = changes[i];
        if (change.category == category &&
            change.kind == BackupChangeKind.added &&
            !appliedKeys.contains(change.key)) {
          changes[i] = BackupChange(
            category,
            change.key,
            change.label,
            BackupChangeKind.limited,
          );
        }
      }
    }
    for (final row in rows) {
      validateBackupRow(category, row);
    }
    rows.sort(
      (a, b) => backupRowKey(category, a).compareTo(backupRowKey(category, b)),
    );
    result[category] = rows;
  }
  return result;
}

Map<String, dynamic> _mergeSeason(
  Map<String, dynamic> local,
  Map<String, dynamic> incoming,
) {
  final items = (local['items'] as List).cast<Map<String, dynamic>>().toList();
  final imported =
      (incoming['items'] as List).cast<Map<String, dynamic>>().toList()..sort(
        (a, b) => (a['sortOrder'] as int).compareTo(b['sortOrder'] as int),
      );
  final ids = {for (final item in items) item['subjectId']};
  final offsets = <int?, int>{};
  for (final item in items) {
    final day = item['weekday'] as int?;
    final order = item['sortOrder'] as int;
    if (order >= (offsets[day] ?? 0)) offsets[day] = order + 1;
  }
  for (final item in imported) {
    if (!ids.add(item['subjectId'])) continue;
    items.add({
      ...item,
      'sortOrder': (item['sortOrder'] as int) + (offsets[item['weekday']] ?? 0),
    });
  }
  return {'season': local['season'], 'items': items};
}
