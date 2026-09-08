import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum BackupCategory {
  schedules('新番表'),
  rss('RSS 订阅与规则'),
  people('备注与屏蔽'),
  pins('首页置顶'),
  browsing('浏览偏好与搜索历史'),
  recommendations('推荐反馈'),
  communityDrafts('社区草稿'),
  privateDrafts('私信草稿');

  const BackupCategory(this.label);
  final String label;
  bool get isDraft => this == communityDrafts || this == privateDrafts;
}

enum BackupImportMode { merge, replace }

class BackupOwner {
  const BackupOwner(this.id, this.username);
  final int id;
  final String username;
  Map<String, dynamic> toJson() => {'id': id, 'username': username};
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef BackupRows = Map<BackupCategory, List<Map<String, dynamic>>>;

String canonicalBackupJson(Object? value) => jsonEncode(_canonical(value));
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String backupDigest(Object? value) =>
    sha256.convert(utf8.encode(canonicalBackupJson(value))).toString();
dynamic _freeze(dynamic value) => value is Map
    ? Map<String, dynamic>.unmodifiable(
        value.map((key, child) => MapEntry(key as String, _freeze(child))),
      )
    : value is List
    ? List<dynamic>.unmodifiable(value.map(_freeze))
    : value;

class BackupArchive {
  BackupArchive._(this.owner, this.createdAt, this.data, this.checksum);
  static const format = 'mubangumi-backup';
  static const version = 1;
  static const maxBytes = 16 * 1024 * 1024;
  static const maxRows = 50000;
  final BackupOwner owner;
  final DateTime createdAt;
  final BackupRows data;
  final String checksum;

  factory BackupArchive.create({
    required BackupOwner owner,
    required BackupRows data,
    DateTime? createdAt,
  }) {
    final payload = _payload(
      owner,
      (createdAt ?? DateTime.now()).toUtc(),
      data,
    );
    return BackupArchive.decode(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({...payload, 'checksum': backupDigest(payload)}),
        ),
      ),
    );
  }

  static Map<String, dynamic> _payload(
    BackupOwner owner,
    DateTime date,
    BackupRows data,
  ) => {
    'format': format,
    'version': version,
    'owner': owner.toJson(),
    'created_at': date.toUtc().toIso8601String(),
    'data': {for (final entry in data.entries) entry.key.name: entry.value},
  };

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({..._payload(owner, createdAt, data), 'checksum': checksum}),
    ),
  );

  factory BackupArchive.decode(Uint8List bytes) {
    if (bytes.length > maxBytes) throw const BackupException('备份超过 16 MB 限制');
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      _checkDepth(text);
      final root = _map(jsonDecode(text), '备份');
      _keys(root, {
        'format',
        'version',
        'owner',
        'created_at',
        'data',
        'checksum',
      });
      if (root['format'] != format ||
          root['version'] is! int ||
          root['version'] != version) {
        throw const BackupException('不支持此备份格式或版本');
      }
      final who = _map(root['owner'], '账号');
      _keys(who, {'id', 'username'});
      _int(who['id'], 1, 0x1fffffffffffff);
      _string(who['username'], 256, nonempty: true);
      final dateText = _string(root['created_at'], 64, nonempty: true);
      final date = DateTime.tryParse(dateText);
      if (date == null || !date.isUtc || dateText != date.toIso8601String()) {
        throw const BackupException('备份时间无效');
      }
      final checksum = _string(root['checksum'], 64);
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
        throw const BackupException('校验信息无效');
      }
      final payload = {...root}..remove('checksum');
      if (backupDigest(payload) != checksum) {
        throw const BackupException('备份校验失败，文件可能已损坏或被修改');
      }
      final raw = _map(root['data'], '数据');
      if (raw.isEmpty ||
          raw.keys.any(
            (key) =>
                !BackupCategory.values.any((category) => category.name == key),
          )) {
        throw const BackupException('备份包含未知或空的数据类别');
      }
      final data = <BackupCategory, List<Map<String, dynamic>>>{};
      var total = 0;
      for (final entry in raw.entries) {
        final category = BackupCategory.values.byName(entry.key);
        final rows = _list(
          entry.value,
          maxRows,
        ).map((row) => _map(row, category.label)).toList();
        total += rows.length;
        if (total > maxRows) throw const BackupException('备份记录过多');
        final keys = <String>{};
        for (final row in rows) {
          validateBackupRow(category, row);
          if (!keys.add(backupRowKey(category, row))) {
            throw BackupException('${category.label}包含重复记录');
          }
          if (category == BackupCategory.schedules) {
            total += (row['items'] as List).length;
          }
        }
        if (total > maxRows) throw const BackupException('备份记录过多');
        if (category == BackupCategory.rss) {
          final urls = {
            for (final row in rows)
              if (row['kind'] == 'source') row['url'],
          };
          if (rows.any(
            (row) =>
                row['kind'] == 'binding' && !urls.contains(row['source_url']),
          )) {
            throw const BackupException('RSS 规则引用了缺失的订阅源');
          }
        }
        if (category == BackupCategory.pins ||
            category == BackupCategory.privateDrafts) {
          _positions(rows);
        }
        if (category == BackupCategory.rss) {
          _positions(rows.where((row) => row['kind'] == 'source').toList());
          _positions(rows.where((row) => row['kind'] == 'binding').toList());
        }
        if (category == BackupCategory.browsing) {
          final history = rows.where((row) => row['kind'] == 'search').toList();
          if (history.length > 12) throw const BackupException('搜索历史超过 12 条');
          _positions(history);
        }
        data[category] = List.unmodifiable(
          rows.map((row) => _freeze(row) as Map<String, dynamic>),
        );
      }
      return BackupArchive._(
        BackupOwner(who['id'] as int, who['username'] as String),
        date,
        Map.unmodifiable(data),
        checksum,
      );
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException('备份内容无效，无法导入');
    }
  }
}

void _checkDepth(String source) {
  var depth = 0;
  var structures = 0;
  var quoted = false;
  var escaped = false;
  for (final char in source.codeUnits) {
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (char == 92) {
        escaped = true;
      } else if (char == 34) {
        quoted = false;
      }
    } else if (char == 34) {
      quoted = true;
    } else if (char == 44) {
      if (++structures > 300000) throw const BackupException('备份结构过大');
    } else if (char == 91 || char == 123) {
      if (++structures > 300000) throw const BackupException('备份结构过大');
      if (++depth > 20) throw const BackupException('备份结构嵌套过深');
    } else if (char == 93 || char == 125) {
      depth--;
    }
  }
}

Map<String, dynamic> _map(Object? value, String label) {
  if (value is! Map<String, dynamic>) throw BackupException('$label格式不正确');
  return value;
}

List<dynamic> _list(Object? value, int max) {
  if (value is! List || value.length > max) {
    throw const BackupException('列表格式或数量无效');
  }
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> keys) {
  if (value.length != keys.length || !keys.containsAll(value.keys)) {
    throw const BackupException('备份字段不完整或含未知字段');
  }
}

String _string(Object? value, int max, {bool nonempty = false}) {
  if (value is! String ||
      value.length > max ||
      (nonempty && value.trim().isEmpty)) {
    throw const BackupException('文本字段无效或过长');
  }
  return value;
}

void _int(Object? value, int min, int max) {
  if (value is! int || value < min || value > max) {
    throw const BackupException('数值字段超出范围');
  }
}

void _bool(Object? value) {
  if (value is! bool) throw const BackupException('开关字段无效');
}

void _oneOf(Object? value, Set<Object?> values) {
  if ((value is num && value is! int) || !values.contains(value)) {
    throw const BackupException('枚举字段无效');
  }
}

void _url(Object? value, {bool empty = false}) {
  final text = _string(value, 8192, nonempty: !empty);
  if (empty && text.isEmpty) return;
  final uri = Uri.tryParse(
    empty && text.startsWith('//') ? 'https:$text' : text,
  );
  if (uri == null ||
      !const ['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    throw const BackupException('链接格式无效');
  }
}

void _positions(List<Map<String, dynamic>> rows) {
  final positions = rows.map((row) => row['position'] as int).toSet();
  if (positions.length != rows.length ||
      positions.any((pos) => pos >= rows.length)) {
    throw const BackupException('排序字段无效');
  }
}

void _season(Object? value) {
  final season = _map(value, '季度');
  _keys(season, {'year', 'quarter'});
  _int(season['year'], 1990, 2100);
  _int(season['quarter'], 0, 3);
}

const _subjectTypes = {1, 2, 3, 4, 6};
void validateBackupRow(BackupCategory category, Map<String, dynamic> row) {
  switch (category) {
    case BackupCategory.schedules:
      _keys(row, {'season', 'items'});
      _season(row['season']);
      final ids = <int>{};
      for (final value in _list(row['items'], 10000)) {
        final item = _map(value, '安排');
        _keys(item, {
          'subjectId',
          'type',
          'name',
          'nameCn',
          'imageUrl',
          'weekday',
          'sortOrder',
          'note',
          'episodeCount',
          'reminderEnabled',
          'reminderHour',
          'reminderMinute',
        });
        _int(item['subjectId'], 1, 0x7fffffff);
        _oneOf(item['type'], _subjectTypes);
        if (!ids.add(item['subjectId'] as int)) {
          throw const BackupException('季度中包含重复作品');
        }
        _string(item['name'], 16384);
        _string(item['nameCn'], 16384);
        _url(item['imageUrl'], empty: true);
        _oneOf(item['weekday'], {null, 1, 2, 3, 4, 5, 6, 7});
        _int(item['sortOrder'], 0, 1000000);
        _string(item['note'], 1048576);
        _int(item['episodeCount'], 0, 1000000);
        _bool(item['reminderEnabled']);
        _int(item['reminderHour'], 0, 23);
        _int(item['reminderMinute'], 0, 59);
        if (item['weekday'] == null && item['reminderEnabled'] == true) {
          throw const BackupException('待安排作品不能开启定时提醒');
        }
      }
    case BackupCategory.rss:
      if (row['kind'] == 'source') {
        _keys(row, {
          'kind',
          'url',
          'name',
          'enabled',
          'created_at',
          'position',
        });
        _url(row['url']);
        _string(row['name'], 4096, nonempty: true);
        _bool(row['enabled']);
      } else {
        _keys(row, {
          'kind',
          'source_url',
          'subject_id',
          'subject_name',
          'season_key',
          'match_keywords',
          'exclude_keywords',
          'enabled',
          'created_at',
          'position',
        });
        _oneOf(row['kind'], {'binding'});
        _url(row['source_url']);
        _int(row['subject_id'], 1, 0x7fffffff);
        _string(row['subject_name'], 16384);
        _string(row['season_key'], 32);
        if (row['season_key'] != '' &&
            !RegExp(
              r'^(19\d{2}|20\d{2}|2100)-Q[0-3]$',
            ).hasMatch(row['season_key'] as String)) {
          throw const BackupException('RSS 季度无效');
        }
        _string(row['match_keywords'], 65536);
        _string(row['exclude_keywords'], 65536);
        _bool(row['enabled']);
      }
      _int(row['created_at'], 0, 7258118400000);
      _int(row['position'], 0, 50000);
    case BackupCategory.people:
      _keys(row, {'username', 'note', 'blocked', 'updated_at'});
      _string(row['username'], 256, nonempty: true);
      if (row['username'] != backupRowKey(category, row)) {
        throw const BackupException('备注账号需要使用规范化的用户名');
      }
      _string(row['note'], 1048576);
      _bool(row['blocked']);
      _int(row['updated_at'], 0, 7258118400000);
    case BackupCategory.pins:
      _keys(row, {'subject_id', 'position'});
      _int(row['subject_id'], 1, 0x7fffffff);
      _int(row['position'], 0, 50000);
    case BackupCategory.browsing:
      switch (row['kind']) {
        case 'library':
          _keys(row, {
            'kind',
            'subject_type',
            'collection_type',
            'progress',
            'sort',
            'minimum_rating',
          });
          _oneOf(row['subject_type'], {null, ..._subjectTypes});
          _oneOf(row['collection_type'], {null, 1, 2, 3, 4, 5});
          _oneOf(row['progress'], {
            'all',
            'notStarted',
            'inProgress',
            'completed',
          });
          _oneOf(row['sort'], {'updated', 'title', 'rating', 'progress'});
          _oneOf(row['minimum_rating'], {0, 6, 7, 8, 9});
        case 'schedule_view':
          _keys(row, {'kind', 'view'});
          _oneOf(row['view'], {'today', 'week', 'board'});
        case 'search':
          _keys(row, {'kind', 'keyword', 'target', 'subject_type', 'position'});
          _string(row['keyword'], 4096, nonempty: true);
          _oneOf(row['target'], {'subject', 'character', 'person'});
          _oneOf(row['subject_type'], _subjectTypes);
          _int(row['position'], 0, 11);
        default:
          throw const BackupException('浏览偏好类型未知');
      }
    case BackupCategory.recommendations:
      _keys(row, {'subject_id', 'title', 'subject_type', 'hidden_at'});
      _int(row['subject_id'], 1, 0x7fffffff);
      _string(row['title'], 16384);
      _oneOf(row['subject_type'], _subjectTypes);
      _int(row['hidden_at'], 0, 7258118400000);
    case BackupCategory.communityDrafts:
      _keys(row, {'target', 'title', 'content', 'updated_at'});
      final target = _list(row['target'], 8);
      if (target.isEmpty) throw const BackupException('社区草稿缺少目标');
      _oneOf(target.first, {'topic', 'group', 'timeline'});
      for (final value in target) {
        if (value is int) {
          _int(value, 0, 0x7fffffff);
        } else {
          _string(value, 512, nonempty: true);
        }
      }
      _string(row['title'], 16384);
      _string(row['content'], 1048576);
      _int(row['updated_at'], 0, 7258118400000);
      if (row['title'] == '' && row['content'] == '') {
        throw const BackupException('备份不应包含已清除的社区草稿');
      }
    case BackupCategory.privateDrafts:
      _keys(row, {
        'id',
        'kind',
        'recipient',
        'title',
        'body',
        'conversation_id',
        'thread_id',
        'updated_at',
        'position',
      });
      _string(row['id'], 1024, nonempty: true);
      _oneOf(row['kind'], {'compose', 'reply'});
      _string(row['recipient'], 1024);
      _string(row['title'], 16384);
      _string(row['body'], 1048576);
      _string(row['conversation_id'], 256);
      _string(row['thread_id'], 256);
      _int(row['updated_at'], 0, 7258118400000);
      _int(row['position'], 0, 50000);
      if (row['kind'] == 'reply') {
        if (row['body'] == '' ||
            (row['conversation_id'] as String).isEmpty ||
            row['id'] !=
                jsonEncode([
                  'reply',
                  row['conversation_id'],
                  row['thread_id'],
                ])) {
          throw const BackupException('回复草稿的目标无效');
        }
      } else if (!RegExp(
            r'^[a-zA-Z0-9_-]{24}$',
          ).hasMatch(row['id'] as String) ||
          row['conversation_id'] != '' ||
          row['thread_id'] != '') {
        throw const BackupException('写信草稿标识无效');
      }
      if ((row['recipient'] as String).trim().isEmpty &&
          row['title'] == '' &&
          row['body'] == '') {
        throw const BackupException('备份不应包含已清除的私信草稿');
      }
  }
}

String backupRowKey(
  BackupCategory category,
  Map<String, dynamic> row,
) => switch (category) {
  BackupCategory.schedules =>
    '${(row['season'] as Map)['year']}-Q${(row['season'] as Map)['quarter']}',
  BackupCategory.rss =>
    row['kind'] == 'source'
        ? jsonEncode(['source', row['url']])
        : jsonEncode(['binding', row['source_url'], row['subject_id']]),
  BackupCategory.people => (row['username'] as String).trim().toLowerCase(),
  BackupCategory.pins ||
  BackupCategory.recommendations => '${row['subject_id']}',
  BackupCategory.browsing =>
    row['kind'] == 'search'
        ? jsonEncode([
            'search',
            row['target'],
            row['target'] == 'subject' ? row['subject_type'] : 0,
            (row['keyword'] as String).trim().toLowerCase(),
          ])
        : '${row['kind']}',
  BackupCategory.communityDrafts => jsonEncode(row['target']),
  BackupCategory.privateDrafts => row['id'] as String,
};

String backupRowLabel(
  BackupCategory category,
  Map<String, dynamic> row,
) => switch (category) {
  BackupCategory.schedules =>
    '${(row['season'] as Map)['year']} ${['冬季', '春季', '夏季', '秋季'][(row['season'] as Map)['quarter'] as int]} · ${(row['items'] as List).length} 部',
  BackupCategory.rss => (row['name'] ?? row['subject_name']) as String,
  BackupCategory.people => row['username'] as String,
  BackupCategory.pins => '作品 ${row['subject_id']}',
  BackupCategory.browsing =>
    row['kind'] == 'search'
        ? row['keyword'] as String
        : row['kind'] == 'library'
        ? '收藏筛选与排序'
        : '新番表视图',
  BackupCategory.recommendations ||
  BackupCategory.privateDrafts ||
  BackupCategory.communityDrafts =>
    (row['title'] as String).isEmpty ? '未命名草稿' : row['title'] as String,
};
