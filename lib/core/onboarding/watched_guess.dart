import '../../models/bangumi_models.dart';

/// Years sampled for a first-run watched guess. Always includes both ends.
List<int> watchedGuessSampleYears(int startYear, int endYear) {
  final first = startYear < 1970 ? 1970 : startYear;
  final last = endYear < first ? first : endYear;
  final years = <int>{first, last};
  for (var year = first; year <= last; year += 3) {
    years.add(year);
  }
  final sorted = years.toList()..sort();
  return sorted;
}

class WatchedCandidate {
  const WatchedCandidate({
    required this.id,
    required this.name,
    this.nameCn = '',
    this.imageUrl = '',
    this.rank = 0,
    this.year = 0,
    this.episodeCount = 0,
    this.score = 0,
    this.tags = const [],
  });

  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final int rank;
  final int year;
  final int episodeCount;
  final double score;
  final List<String> tags;

  String get displayName {
    final chinese = nameCn.trim();
    return chinese.isNotEmpty ? chinese : name;
  }

  factory WatchedCandidate.fromSubject(Subject subject) => WatchedCandidate(
    id: subject.id,
    name: subject.name,
    nameCn: subject.nameCn,
    imageUrl: subject.imageUrl,
    rank: subject.rank,
    year: _yearOf(subject.date),
    episodeCount: subject.episodeCount,
    score: subject.score,
    tags: subject.tags,
  );

  Subject toSubject() => Subject(
    id: id,
    name: name,
    nameCn: nameCn,
    imageUrl: imageUrl,
    summary: '',
    episodeCount: episodeCount,
    score: score,
    rank: rank,
    date: year > 0 ? '$year' : '',
    type: SubjectType.anime,
    tags: tags,
  );
}

class WatchedGuess {
  const WatchedGuess(this.candidate, this.reason);
  final WatchedCandidate candidate;
  final String reason;
}

/// Orders likely-watched anime from ranks, then from what the user just confirmed.
class WatchedGuessRanker {
  WatchedGuessRanker({
    Iterable<WatchedCandidate> alreadyAccepted = const [],
    this.coolAfter = 3,
  }) {
    for (final item in alreadyAccepted) {
      if (item.id <= 0 || !accepted.add(item.id)) continue;
      acceptedItems.add(item);
      add(item);
    }
  }

  final int coolAfter;
  final accepted = <int>{};
  final rejected = <int>{};
  final acceptedItems = <WatchedCandidate>[];
  final _pool = <int, WatchedCandidate>{};
  final _because = <int, int>{};
  final _tagStreak = <String, int>{};
  final _cooled = <String>{};
  final _owned = <int>{};
  final _tagOwners = <String, int>{};
  List<WatchedCandidate>? _ordered;

  int get remainingCount => _pool.values.where(_pending).length;

  bool _pending(WatchedCandidate item) =>
      !_owned.contains(item.id) &&
      !accepted.contains(item.id) &&
      !rejected.contains(item.id);

  void excludeOwned(Iterable<int> ids) {
    for (final id in ids) {
      if (id <= 0) continue;
      _owned.add(id);
      final removed = _pool.remove(id);
      if (removed != null) _countTags(removed, -1);
      _because.remove(id);
    }
    _ordered = null;
  }

  bool owns(int id) => _owned.contains(id);

  void addSubjects(Iterable<Subject> subjects) {
    for (final subject in subjects) {
      if (subject.id <= 0 ||
          subject.nsfw ||
          subject.type != SubjectType.anime) {
        continue;
      }
      add(WatchedCandidate.fromSubject(subject));
    }
  }

  void add(WatchedCandidate item) {
    if (item.id <= 0 || _owned.contains(item.id)) return;
    if (_pool.containsKey(item.id)) return;
    _pool[item.id] = item;
    _countTags(item, 1);
    _ordered = null;
  }

  void _countTags(WatchedCandidate item, int delta) {
    for (final tag in item.tags.map((tag) => tag.trim()).toSet()) {
      if (tag.isEmpty) continue;
      final count = (_tagOwners[tag] ?? 0) + delta;
      if (count <= 0) {
        _tagOwners.remove(tag);
      } else {
        _tagOwners[tag] = count;
      }
    }
  }

  void accept(
    WatchedCandidate item, {
    Iterable<WatchedCandidate> related = const [],
  }) {
    if (item.id <= 0) return;
    add(item);
    rejected.remove(item.id);
    if (accepted.add(item.id)) acceptedItems.add(item);
    _tagStreak.clear();
    _cooled.clear();
    _ordered = null;
    noteRelated(item.id, related);
  }

  void noteRelated(int acceptedId, Iterable<WatchedCandidate> related) {
    if (!accepted.contains(acceptedId)) return;
    for (final item in related) {
      if (item.id <= 0 ||
          item.id == acceptedId ||
          _owned.contains(item.id) ||
          accepted.contains(item.id) ||
          rejected.contains(item.id)) {
        continue;
      }
      add(item);
      _because.putIfAbsent(item.id, () => acceptedId);
    }
    _ordered = null;
  }

  void reject(WatchedCandidate item) {
    if (item.id <= 0) return;
    add(item);
    rejected.add(item.id);
    _ordered = null;
    if (accepted.remove(item.id)) {
      acceptedItems.removeWhere((other) => other.id == item.id);
    }
    final tags = _specificTags(item).toSet();
    if (tags.isEmpty) {
      _tagStreak.clear();
      _cooled.clear();
      return;
    }
    for (final tag in tags) {
      final next = (_tagStreak[tag] ?? 0) + 1;
      _tagStreak[tag] = next;
      if (next >= coolAfter) _cooled.add(tag);
    }
    for (final tag in _tagStreak.keys.toList()) {
      if (tags.contains(tag)) continue;
      _tagStreak[tag] = 0;
      _cooled.remove(tag);
    }
  }

  void undoAccept(int id) {
    if (!accepted.remove(id)) return;
    acceptedItems.removeWhere((item) => item.id == id);
    _because.removeWhere((_, from) => from == id);
    _ordered = null;
  }

  void undoReject(int id) {
    if (!rejected.remove(id)) return;
    _tagStreak.clear();
    _cooled.clear();
    _ordered = null;
  }

  List<WatchedGuess> next({int count = 4}) {
    if (_ordered == null) {
      final cooled = <int>{
        if (_cooled.isNotEmpty)
          for (final item in _pool.values)
            if (_isCooled(item)) item.id,
      };
      _ordered = _pool.values.where(_pending).toList()
        ..sort((a, b) {
          if (cooled.contains(a.id) != cooled.contains(b.id)) {
            return cooled.contains(a.id) ? 1 : -1;
          }
          final aBoost = _because.containsKey(a.id);
          final bBoost = _because.containsKey(b.id);
          if (aBoost != bBoost) return aBoost ? -1 : 1;
          final rank = _rankKey(a).compareTo(_rankKey(b));
          if (rank != 0) return rank;
          return a.id.compareTo(b.id);
        });
    }
    return [
      for (final item in _ordered!.take(count))
        WatchedGuess(item, reasonFor(item)),
    ];
  }

  String reasonFor(WatchedCandidate item) {
    final from = _because[item.id];
    if (from != null) {
      final source = _pool[from];
      return '和${source?.displayName ?? '看过的作品'}相近';
    }
    if (item.year > 0) return '${item.year} 年高排名';
    return '很多人看过';
  }

  bool _isCooled(WatchedCandidate item) {
    if (_because.containsKey(item.id)) return false;
    return _specificTags(item).any(_cooled.contains);
  }

  Iterable<String> _specificTags(WatchedCandidate item) sync* {
    for (final tag in item.tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty) continue;
      final owners = _tagOwners[trimmed] ?? 0;
      if (_pool.length < 5 || owners * 5 <= _pool.length * 2) yield trimmed;
    }
  }

  static int _rankKey(WatchedCandidate item) =>
      item.rank > 0 ? item.rank : 1 << 20;
}

int _yearOf(String date) {
  final match = RegExp(r'^(\d{4})').firstMatch(date.trim());
  return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
}
