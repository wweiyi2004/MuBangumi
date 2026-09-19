import 'dart:collection';
import 'protocol.dart';

abstract final class RoomLimits {
  static const snapshotBytes = 8 * 1024 * 1024;
  static const snapshotComments = 20;
  static const commentPageSize = 50;
  static const maxCommentPageSize = 100;
  static const maxRounds = 100;
  static const maxMembers = 500;
}

enum RoundStatus { waiting, open, paused, closed }

enum RoomAction {
  create,
  rename,
  add,
  remove,
  move,
  start,
  pause,
  resume,
  close,
  publish,
  comments,
  hide,
  end,
  rotateInvite,
  score,
  comment,
}

Never _invalid(String field) =>
    throw FormatException('Invalid room field: $field');
bool sameRoomEpoch(Json? a, Json b) => a?['serverEpoch'] == b['serverEpoch'];
Json _map(Object? value, String name) =>
    value is Map<String, dynamic> ? value : _invalid(name);
String _text(Json data, String key, {int max = 200, bool empty = false}) {
  final value = data[key];
  if (value is! String ||
      (!empty && value.trim().isEmpty) ||
      value.runes.length > max)
    _invalid(key);
  if (key == 'id' && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value))
    _invalid(key);
  return value;
}

int _int(
  Json data,
  String key, {
  int min = 0,
  int max = 0x7fffffff,
  int? fallback,
}) {
  final value = data[key] ?? fallback;
  if (value is! int || value < min || value > max) _invalid(key);
  return value;
}

bool _bool(Json data, String key, {bool? fallback}) {
  final value = data[key] ?? fallback;
  if (value is! bool) _invalid(key);
  return value;
}

class RoomComment {
  RoomComment.fromJson(Json data)
    : id = _text(data, 'id'),
      text = _text(data, 'text', max: 500),
      hidden = _bool(data, 'hidden', fallback: false),
      mine = _bool(data, 'mine', fallback: false),
      _json = Map.unmodifiable(data);
  final String id, text;
  final bool hidden, mine;
  final Json _json;
  Json toJson() => _json;
}

class RoomStatistics {
  RoomStatistics.fromJson(Json data) : count = _int(data, 'count', max: 500) {
    final d = data['distribution'];
    if (d is! List ||
        d.length != 10 ||
        d.any((v) => v is! int || v < 0 || v > 500))
      _invalid('distribution');
    distribution = List<int>.unmodifiable(d.cast<int>());
    if (distribution.fold<int>(0, (a, b) => a + b) != count) _invalid('count');
    final v = data['mean'];
    if (v != null && (v is! num || !v.isFinite || v < 1 || v > 10))
      _invalid('mean');
    mean = (v as num?)?.toDouble();
    if ((count == 0) != (mean == null)) _invalid('mean');
  }
  final int count;
  late final double? mean;
  late final List<int> distribution;
}

class RoundSnapshot {
  factory RoundSnapshot.fromJson(Json data) =>
      data is _RoundJson ? data.value : RoundSnapshot._parse(data);
  RoundSnapshot._parse(Json data)
    : id = _text(data, 'id'),
      count = _int(data, 'count', max: 500),
      published = _bool(data, 'published'),
      publicComments = _bool(data, 'publicComments') {
    status =
        RoundStatus.values.where((s) => s.name == data['status']).firstOrNull ??
        _invalid('status');
    final subject = _map(data['subject'], 'subject');
    subjectId = _int(subject, 'id', min: 1);
    title = _text(subject, 'title');
    if (subject['cover'] != null) {
      final cover = _text(subject, 'cover', max: 64, empty: true);
      if (cover.isNotEmpty && !RegExp(r'^[a-f0-9]{64}$').hasMatch(cover))
        _invalid('cover');
    }
    if (subject['summary'] != null)
      _text(subject, 'summary', max: 6000, empty: true);
    final score = data['myScore'];
    if (score != null && (score is! int || score < 1 || score > 10))
      _invalid('myScore');
    myScore = score as int?;
    statistics = data['stats'] == null
        ? null
        : RoomStatistics.fromJson(_map(data['stats'], 'stats'));
    if (statistics != null && statistics!.count != count)
      _invalid('stats.count');
    final raw = data['comments'];
    if (raw is! List || raw.length > 5000) _invalid('comments');
    comments = List.unmodifiable(
      raw.map((c) => RoomComment.fromJson(_map(c, 'comment'))),
    );
    commentsTotal = _int(
      data,
      'commentsTotal',
      fallback: comments.length,
      min: comments.length,
      max: 5000,
    );
    commentsMore = _bool(data, 'commentsMore', fallback: false);
    _json = Map.unmodifiable({
      ...data,
      'subject': Map<String, dynamic>.unmodifiable(subject),
      if (statistics != null)
        'stats': Map<String, dynamic>.unmodifiable({
          'count': statistics!.count,
          'mean': statistics!.mean,
          'distribution': statistics!.distribution,
        }),
      'comments': List.unmodifiable(comments.map((c) => c.toJson())),
    });
  }
  final String id;
  final int count;
  final bool published, publicComments;
  late final RoundStatus status;
  late final int subjectId, commentsTotal;
  late final String title;
  late final int? myScore;
  late final RoomStatistics? statistics;
  late final List<RoomComment> comments;
  late final bool commentsMore;
  late final Json _json;
  Json toJson() => _RoundJson(this);
}

class RoomSnapshot {
  factory RoomSnapshot.fromJson(Json data) =>
      data is _SnapshotJson ? data.value : RoomSnapshot._parse(data);
  RoomSnapshot._parse(Json data)
    : id = _text(data, 'id'),
      title = _text(data, 'title', max: 80),
      ended = _bool(data, 'ended'),
      version = _int(data, 'version', min: 1),
      memberCount = _int(data, 'memberCount', max: 500) {
    hasRevision = data['revision'] != null;
    revision = _int(data, 'revision', fallback: version, min: 1);
    final raw = data['rounds'];
    if (raw is! List || raw.length > 100) _invalid('rounds');
    rounds = List.unmodifiable(
      raw.map((r) => RoundSnapshot.fromJson(_map(r, 'round'))),
    );
    if (rounds.map((r) => r.id).toSet().length != rounds.length)
      _invalid('round IDs');
    final current = data['current'];
    if (current != null &&
        (current is! String || !rounds.any((r) => r.id == current)))
      _invalid('current');
    currentId = current as String?;
    final rawMembers = data['members'];
    List<Json>? members;
    if (rawMembers != null) {
      if (rawMembers is! List || rawMembers.length > RoomLimits.maxMembers)
        _invalid('members');
      members = List.unmodifiable(
        rawMembers.map((raw) {
          final m = _map(raw, 'member');
          return Map<String, dynamic>.unmodifiable({
            'name': _text(m, 'name', max: 40),
            'submitted': _bool(m, 'submitted'),
          });
        }),
      );
    }
    _json = Map.unmodifiable({
      ...data,
      'rounds': List.unmodifiable(rounds.map((r) => r.toJson())),
      if (members != null) 'members': members,
    });
  }
  final String id, title;
  final bool ended;
  final int version, memberCount;
  late final int revision;
  late final bool hasRevision;
  late final String? currentId;
  late final List<RoundSnapshot> rounds;
  late final Json _json;
  RoundSnapshot? get current =>
      rounds.where((r) => r.id == currentId).firstOrNull;
  Json toJson() => _SnapshotJson(this);
}

class RoomCommentsPage {
  RoomCommentsPage.fromJson(Json data)
    : eventId = _text(data, 'event'),
      roundId = _text(data, 'round'),
      revision = _int(data, 'revision', min: 1),
      total = _int(data, 'total', max: 5000) {
    final raw = data['comments'];
    if (raw is! List || raw.length > RoomLimits.maxCommentPageSize)
      _invalid('comments');
    comments = List.unmodifiable(
      raw.map((c) => RoomComment.fromJson(_map(c, 'comment'))),
    );
    nextCursor = data['nextCursor'] == null
        ? null
        : _int(data, 'nextCursor', min: 1);
  }
  final String eventId, roundId;
  final int revision, total;
  late final int? nextCursor;
  late final List<RoomComment> comments;
}

class RoomCommand {
  RoomCommand.fromJson(Json data, {required bool participant}) {
    action =
        RoomAction.values.where((v) => v.name == data['action']).firstOrNull ??
        _invalid('action');
    if (participant !=
        (action == RoomAction.score || action == RoomAction.comment))
      _invalid('action role');
    op = _text(data, 'op', max: 80);
    if (action != RoomAction.create) eventId = _text(data, 'event');
    if (!participant && action != RoomAction.create)
      version = _int(data, 'version', min: 1);
    if (participant) roundId = _text(data, 'round');
    if (action == RoomAction.score)
      score = _int(data, 'score', min: 1, max: 10);
    if (action == RoomAction.comment) text = _text(data, 'text', max: 500);
    _json = Map.unmodifiable(data);
  }
  late final RoomAction action;
  late final String op;
  String? eventId, roundId, text;
  int? version, score;
  late final Json _json;
  Json toJson() => _json;
}

/// Structural changes always carry a full snapshot. A delta replaces complete
/// round projections, so removing a comment or withdrawing results cannot leave
/// a previously visible field behind in a client's cache.
Json mergeRoomSnapshot(Json? previous, Json payload) {
  if (payload['type'] != 'delta')
    return RoomSnapshot.fromJson(payload).toJson();
  if (previous == null ||
      !sameRoomEpoch(previous, payload) ||
      previous['id'] != payload['id'] ||
      previous['revision'] != payload['baseRevision']) {
    throw const FormatException('Room snapshot requires resynchronization');
  }
  final changes = payload['rounds'];
  if (changes is! List || changes.length > RoomLimits.maxRounds)
    _invalid('delta.rounds');
  final replacements = {
    for (final raw in changes)
      _text(_map(raw, 'round'), 'id'): _map(raw, 'round'),
  };
  if (replacements.length != changes.length) _invalid('delta round IDs');
  final oldRounds = (previous['rounds'] as List).cast<Json>();
  if (replacements.keys.any((id) => !oldRounds.any((r) => r['id'] == id)))
    _invalid('delta.round');
  final merged =
      <String, dynamic>{
          ...previous,
          ...payload,
          'rounds': [for (final r in oldRounds) replacements[r['id']] ?? r],
        }
        ..remove('type')
        ..remove('baseRevision');
  if (_int(merged, 'revision', min: 1) < _int(previous, 'revision', min: 1))
    _invalid('delta.revision');
  return RoomSnapshot.fromJson(merged).toJson();
}

class _RoundJson extends UnmodifiableMapView<String, dynamic> {
  _RoundJson(this.value) : super(value._json);
  final RoundSnapshot value;
}

class _SnapshotJson extends UnmodifiableMapView<String, dynamic> {
  _SnapshotJson(this.value) : super(value._json);
  final RoomSnapshot value;
}
