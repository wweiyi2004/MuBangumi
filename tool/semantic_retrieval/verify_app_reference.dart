// Verify the Python reference scores against the application's actual engine.
// Uses public work metadata and an empty taste profile; no network/session.
import 'dart:convert';
import 'dart:io';

import 'package:mubangumi/core/recommend/fan_recommend_engine.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main(List<String> args) {
  if (args.length != 3) {
    throw ArgumentError(
      'Expected corpus.jsonl evaluation_queries.json output.json',
    );
  }
  final rows = File(args[0])
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();
  final subjects = [
    for (final r in rows)
      Subject(
        id: r['subject_id'] as int,
        name: r['name'] as String,
        nameCn: r['name_cn'] as String,
        imageUrl: '',
        summary: r['summary'] as String,
        episodeCount: (r['episodes'] as int?) ?? 0,
        score: (r['score'] as num).toDouble(),
        rank: r['rank'] as int,
        date: '',
        ratingTotal: r['rating_total'] as int,
        tags: (r['tags'] as List).cast<String>(),
      ),
  ];
  final spec = jsonDecode(File(args[1]).readAsStringSync()) as Map;
  const taste = FanTasteProfile(topTags: [], ownedIds: {});
  final scores = <String, List<double>>{};
  for (final q in spec['queries'] as List) {
    final request = FanRecommendRequest(
      wishText: (q['retrieval_text'] ?? q['text']) as String,
      minimumRating: 0,
      useTaste: false,
    );
    scores[q['id'] as String] = [
      for (final subject in subjects)
        FanRecommendEngine.rank(
          candidates: [subject],
          taste: taste,
          request: request,
        ).single.score,
    ];
  }
  File(args[2]).writeAsStringSync(jsonEncode(scores));
  stdout.writeln(
    'Scored ${scores.length} queries × ${subjects.length} works with the actual Dart engine.',
  );
}
