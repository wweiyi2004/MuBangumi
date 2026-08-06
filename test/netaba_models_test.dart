import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/netaba_models.dart';

void main() {
  test('parses subject history score rank and collect snapshots', () {
    final history = NetabaSubjectHistory.fromJson({
      'subject': {
        'name': 'ダンジョン飯',
        'name_cn': '迷宫饭',
        'air_date': '2024-01-04T00:00:00Z',
        'score': 7.85,
        'rank': 359,
        'images': {'large': 'https://example.com/a.jpg'},
      },
      'history': [
        {
          'bgmId': 395378,
          'recordedAt': '2022-08-08T16:00:00Z',
          'collect': {'wish': 10, 'collect': 1},
        },
        {
          'bgmId': 395378,
          'recordedAt': '2024-01-05T16:00:00Z',
          'rank': 475,
          'score': 7.75,
          'rating': {
            'total': 100,
            'count': {'1': 1, '10': 9},
          },
          'collect': {
            'wish': 100,
            'collect': 200,
            'doing': 50,
            'on_hold': 5,
            'dropped': 3,
          },
        },
        {
          'bgmId': 395378,
          'recordedAt': '2026-08-05T16:00:00Z',
          'rank': 359,
          'score': 7.85,
          'rating': {
            'total': 17792,
            'count': {
              '1': 9,
              '2': 12,
              '3': 14,
              '4': 47,
              '5': 198,
              '6': 852,
              '7': 4185,
              '8': 9146,
              '9': 2517,
              '10': 812,
            },
          },
          'collect': {
            'wish': 5124,
            'collect': 27030,
            'doing': 5512,
            'on_hold': 2073,
            'dropped': 807,
          },
        },
      ],
    });

    expect(history.subject.displayName, '迷宫饭');
    expect(history.history, hasLength(3));
    expect(history.history.first.hasScore, isFalse);
    expect(history.history[1].rank, 475);
    expect(history.history.last.score, closeTo(7.85, 0.001));
    expect(history.history.last.collect.doing, 5512);
    expect(history.scoreSeries(), hasLength(2));
    expect(history.rankSeries(), hasLength(2));

    final delta = history.delta(days: 30);
    // First point is years earlier, so baseline falls back beyond 30d window.
    expect(delta, isNotNull);
    expect(delta!.score, closeTo(0.1, 0.001));
    expect(delta.rank, 359 - 475);
  });

  test('parses trending movers and sparkline', () {
    final trending = NetabaTrending.fromJson({
      'up': [
        {
          'bgmId': 325767,
          'score': 0.43,
          'subject': {
            'name': '対ありでした。',
            'name_cn': '感谢对战。',
          },
          'history': [
            {
              'recordedAt': '2026-07-07T16:00:00Z',
              'score': 6.42,
              'rating': {
                'total': 103,
                'count': {'6': 43, '7': 37},
              },
            },
            {
              'recordedAt': '2026-08-05T16:00:00Z',
              'score': 6.96,
              'rating': {
                'total': 763,
                'count': {'6': 132, '7': 395},
              },
            },
          ],
        },
      ],
      'down': [],
      'done': [],
    });

    expect(trending.up, hasLength(1));
    final item = trending.up.first;
    expect(item.displayName, '感谢对战。');
    expect(item.scoreDelta, closeTo(0.43, 0.001));
    expect(item.latestScore, closeTo(6.96, 0.001));
    expect(item.sparkline(), hasLength(2));
  });

  test('downsamples dense history for charts', () {
    final points = [
      for (var i = 0; i < 1000; i++)
        NetabaHistoryPoint(
          recordedAt: DateTime.utc(2020, 1, 1).add(Duration(days: i)),
          score: 6 + i / 1000,
          rank: 1000 - i,
        ),
    ];
    final history = NetabaSubjectHistory(
      subject: const NetabaSubjectInfo(name: 'A', nameCn: '甲'),
      history: points,
    );
    final series = history.scoreSeries(maxPoints: 100);
    expect(series.length, lessThanOrEqualTo(100));
    expect(series.first.value, closeTo(6, 0.001));
    expect(series.last.value, closeTo(6.999, 0.01));
  });
}
