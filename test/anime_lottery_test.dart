import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/recommend/anime_lottery.dart';
import 'package:mubangumi/models/anime_lottery.dart';
import 'package:mubangumi/models/bangumi_models.dart';

Subject _subject(int id, double score, {int type = 2, bool nsfw = false}) =>
    Subject.fromJson({
      'id': id,
      'type': type,
      'name': '抽签作品$id',
      'rating': {'score': score},
      'nsfw': nsfw,
    });
UserCollection _collection(
  int id,
  CollectionType type, {
  int progress = 0,
  int rate = 0,
}) => UserCollection(
  subjectId: id,
  type: type,
  rate: rate,
  episodeStatus: progress,
  updatedAt: null,
  subject: _subject(id, 8),
);

void main() {
  test(
    'prizes include boundary ratings and reject unscored, wrong type and NSFW',
    () {
      expect(AnimePrize.good.permits(_subject(1, 8)), true);
      expect(AnimePrize.good.permits(_subject(1, 7.99)), false);
      expect(AnimePrize.bad.permits(_subject(1, 5)), true);
      for (final value in [0.0, 5.01, double.nan]) {
        expect(AnimePrize.bad.permits(_subject(1, value)), false);
      }
      expect(AnimePrize.good.permits(_subject(1, 8, type: 1)), false);
      expect(AnimePrize.good.permits(_subject(1, 8, nsfw: true)), false);
    },
  );
  test(
    'untouched wishes remain eligible; started wishes and every watch status are excluded',
    () {
      expect(
        AnimeLottery.watchedIds([
          _collection(1, CollectionType.wish),
          _collection(2, CollectionType.wish, progress: 1),
          _collection(3, CollectionType.wish, rate: 8),
          for (final type in CollectionType.values.where(
            (t) => t != CollectionType.wish,
          ))
            _collection(type.value + 10, type),
        ]),
        {2, 3, 12, 13, 14, 15},
      );
    },
  );
  test(
    'samples another page after watched candidates and rechecks all ratings locally',
    () async {
      final offsets = <int>[];
      final result = await AnimeLottery(random: _ZeroRandom()).draw(
        prize: AnimePrize.good,
        fetch: (offset, limit) async {
          offsets.add(offset);
          return AnimeLotteryPage(
            total: 100,
            subjects: offset == 0
                ? [_subject(1, 8)]
                : [_subject(2, 7.9), _subject(3, 8), _subject(4, 8, type: 1)],
          );
        },
        excludedIds: () => {1},
        isCurrent: () => true,
      );
      expect(offsets, [0, 50]);
      expect(result?.id, 3);
    },
  );
  test(
    'late account response and newly excluded candidate never produce a result',
    () async {
      final pending = Completer<AnimeLotteryPage>();
      var current = true;
      final result = AnimeLottery().draw(
        prize: AnimePrize.good,
        fetch: (_, _) => pending.future,
        excludedIds: () => {},
        isCurrent: () => current,
      );
      current = false;
      pending.complete(AnimeLotteryPage(total: 1, subjects: [_subject(1, 8)]));
      expect(await result, isNull);
      final excluded = <int>{};
      expect(
        await AnimeLottery().draw(
          prize: AnimePrize.good,
          fetch: (_, _) async {
            excluded.add(1);
            return AnimeLotteryPage(total: 1, subjects: [_subject(1, 8)]);
          },
          excludedIds: () => excluded,
          isCurrent: () => true,
        ),
        isNull,
      );
    },
  );
  test(
    'rated catalog sends inclusive lower and upper bounds with no keyword restriction',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/v0'));
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'total': 120, 'data': []},
              ),
            );
          },
        ),
      );
      final api = BangumiApi(dio: dio);
      for (final prize in AnimePrize.values) {
        expect((await api.getAnimeLotteryPage(prize, offset: 50)).total, 120);
        final data = requests.last.data as Map;
        expect(data['keyword'], '');
        expect((data['filter'] as Map)['rating'], [
          '>0',
          '>=${prize.minimum}',
          '<=${prize.maximum}',
        ]);
        expect((data['filter'] as Map)['type'], [2]);
        expect(requests.last.queryParameters['offset'], 50);
      }
    },
  );
}

class _ZeroRandom implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}
