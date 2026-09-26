import 'protocol.dart';

/// One title in the whole-activity ranking.
class RoomSummaryEntry {
  const RoomSummaryEntry({
    required this.rank,
    required this.round,
    required this.title,
    required this.cover,
    required this.mean,
    required this.count,
    this.myScore,
  });
  final int rank, count;
  final String round, title, cover;
  final double mean;
  final int? myScore;
}

/// Ranks every round whose statistics this viewer can see, highest mean
/// first. Equal means share a rank ("1, 1, 3"); more ratings, then playlist
/// order break display ties. Unrated rounds are left out. `web/app.js` keeps
/// the same rule for the browser pages.
List<RoomSummaryEntry> roomSummary(Json? event) {
  final rounds = ((event?['rounds'] as List?) ?? const []).cast<Json>();
  final rated = [
    for (final (i, r) in rounds.indexed)
      if (r['stats'] is Json && (r['stats']['count'] as int? ?? 0) > 0)
        (order: i, round: r, mean: (r['stats']['mean'] as num).toDouble()),
  ];
  rated.sort((a, b) {
    final byMean = b.mean.compareTo(a.mean);
    if (byMean != 0) return byMean;
    final byCount = (b.round['stats']['count'] as int).compareTo(
      a.round['stats']['count'] as int,
    );
    return byCount != 0 ? byCount : a.order.compareTo(b.order);
  });
  final result = <RoomSummaryEntry>[];
  for (final (i, item) in rated.indexed) {
    final r = item.round;
    result.add(
      RoomSummaryEntry(
        rank: i > 0 && rated[i - 1].mean == item.mean
            ? result[i - 1].rank
            : i + 1,
        round: r['id'] as String,
        title: r['subject']['title'] as String,
        cover: r['subject']['cover'] as String? ?? '',
        mean: item.mean,
        count: r['stats']['count'] as int,
        myScore: r['myScore'] as int?,
      ),
    );
  }
  return result;
}
