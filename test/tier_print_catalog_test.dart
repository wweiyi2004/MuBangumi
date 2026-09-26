import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/tier_print/tier_print_catalog.dart';
import 'package:mubangumi/features/tier_print/tier_print_models.dart';

Map<String, Object> item(int id, int month, {String? date}) => {
  'id': id,
  'type': 2,
  'name': '条目$id',
  'date': date ?? '2025-${month.toString().padLeft(2, '0')}-01',
  'platform': 'TV',
  'images': {'large': 'https://lain.bgm.tv/fixture$id.jpg'},
};
TierPrintCatalog catalog(
  Map<String, dynamic> Function(RequestOptions) respond,
) {
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: respond(request),
            ),
          );
        },
      ),
    );
  final result = TierPrintCatalog(dio: dio);
  addTearDown(result.close);
  return result;
}

void main() {
  test(
    'catalogued subject without an exact date is retained and clearly labelled',
    () async {
      final service = catalog(
        (r) => r.queryParameters['month'] == 1
            ? {
                'total': 2,
                'data': [item(1, 1, date: ''), item(2, 1)],
              }
            : {'total': 0, 'data': []},
      );
      final result = await service.load(
        const TierPrintPeriod(year: 2025, quarter: 1),
      );
      expect(result.entries.map((e) => e.id), [2, 1]);
      expect(result.entries.last.dateLabel, '日期未提供');
      expect(result.entries.last.catalogMonth, 1);
    },
  );
  test(
    'quarter walks every page in all three months then sorts deterministically',
    () async {
      final calls = <String>[];
      final service = catalog((r) {
        final month = r.queryParameters['month'] as int,
            offset = r.queryParameters['offset'] as int;
        calls.add('$month:$offset');
        expect(r.method, 'GET');
        expect(r.queryParameters['type'], 2);
        return month == 1
            ? {
                'total': 3,
                'data': offset == 0 ? [item(2, 1), item(1, 1)] : [item(3, 1)],
              }
            : {
                'total': 1,
                'data': [item(month * 10, month)],
              };
      });
      final result = await service.load(
        const TierPrintPeriod(year: 2025, quarter: 1),
      );
      expect(calls, ['1:0', '1:2', '2:0', '3:0']);
      expect(result.entries.map((e) => e.id), [1, 2, 3, 20, 30]);
      expect(result.sourceCount, 5);
    },
  );
  test(
    'annual export reads all twelve months, not only quarter starting months',
    () async {
      final months = <int>[];
      final service = catalog((r) {
        final month = r.queryParameters['month'] as int;
        months.add(month);
        return {
          'total': 1,
          'data': [item(month, month)],
        };
      });
      expect(
        (await service.load(const TierPrintPeriod(year: 2025))).entries,
        hasLength(12),
      );
      expect(months, List.generate(12, (i) => i + 1));
    },
  );
  for (final failure in [
    'duplicate',
    'truncated',
    'changed-total',
    'outside-period',
    'invalid-item',
  ]) {
    test(
      'incomplete $failure result is never published as a complete catalogue',
      () async {
        final service = catalog((r) {
          final offset = r.queryParameters['offset'];
          if (offset == 0) {
            return {
              'total': 2,
              'data': [item(1, 1)],
            };
          }
          return switch (failure) {
            'duplicate' => {
              'total': 2,
              'data': [item(1, 1)],
            },
            'truncated' => {'total': 2, 'data': []},
            'changed-total' => {
              'total': 3,
              'data': [item(2, 1)],
            },
            'outside-period' => {
              'total': 2,
              'data': [item(2, 2)],
            },
            _ => {
              'total': 2,
              'data': [<String, dynamic>{}],
            },
          };
        });
        await expectLater(
          service.load(const TierPrintPeriod(year: 2025, quarter: 1)),
          throwsA(isA<FormatException>()),
        );
      },
    );
  }
  test('cancelled catalogue does not request more pages', () async {
    var requests = 0;
    final cancel = CancelToken()..cancel();
    final service = catalog((r) {
      requests++;
      return {'total': 0, 'data': []};
    });
    await expectLater(
      service.load(const TierPrintPeriod(year: 2025), cancel: cancel),
      throwsA(isA<DioException>()),
    );
    expect(requests, 0);
  });
}
