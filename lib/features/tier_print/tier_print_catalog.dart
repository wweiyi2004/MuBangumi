import 'package:dio/dio.dart';
import '../../core/network/bangumi_user_agent.dart';
import '../../models/bangumi_models.dart';
import 'tier_print_models.dart';
import 'tier_print_cancel.dart';

/// Independent public catalogue reader; it never changes OAuth or website state.
class TierPrintCatalog {
  TierPrintCatalog({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.bgm.tv/v0',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 25),
              headers: {'User-Agent': muBangumiUserAgent},
            ),
          );
  final Dio _dio;
  void close() => _dio.close(force: true);

  Future<TierCatalogResult> load(
    TierPrintPeriod period, {
    CancelToken? cancel,
    void Function(String)? progress,
  }) async {
    if (!period.valid) throw const FormatException('年份或季度无效');
    final entries = <int, TierPrintEntry>{};
    var sourceCount = 0;
    for (final month in period.months) {
      var offset = 0;
      int? total;
      final monthIds = <int>{};
      while (total == null || offset < total) {
        cancel?.throwIfCancellationRequested();
        progress?.call(
          '读取 ${period.year} 年 $month 月：$offset / ${total ?? '…'}',
        );
        final response = await _dio.get<Map<String, dynamic>>(
          '/subjects',
          queryParameters: {
            'type': 2,
            'year': period.year,
            'month': month,
            'sort': 'date',
            'limit': 50,
            'offset': offset,
          },
          cancelToken: cancel,
        );
        cancel?.throwIfCancellationRequested();
        final json = response.data;
        final rows = json?['data'];
        final count = json?['total'];
        if (rows is! List ||
            count is! int ||
            count < 0 ||
            count > 10000 ||
            (total != null && count != total) ||
            (rows.isEmpty && offset < count)) {
          throw const FormatException('目录不完整或在读取中发生变化，请重新读取；不会导出残缺清单');
        }
        total = count;
        if (sourceCount + total > 10000) {
          throw const FormatException('条目过多，请缩小到一个季度');
        }
        for (final raw in rows) {
          if (raw is! Map) throw const FormatException('目录数据不完整，请重试');
          final subject = Subject.fromJson(Map<String, dynamic>.from(raw));
          final images = raw['images'];
          final medium = images is Map ? images['medium'] : null;
          if (subject.id <= 0 ||
              subject.displayName.trim().isEmpty ||
              subject.type != SubjectType.anime ||
              !monthIds.add(subject.id)) {
            throw const FormatException('目录包含异常或重复分页，请重新读取');
          }
          final date = DateTime.tryParse(subject.date);
          if (subject.date.isNotEmpty &&
              (date == null ||
                  date.year != period.year ||
                  date.month != month)) {
            throw const FormatException('目录返回了不在所选月份的条目，请稍后重新读取');
          }
          entries[subject.id] = TierPrintEntry(
            id: subject.id,
            title: subject.displayName,
            date: subject.date,
            coverUrl: medium is String && medium.isNotEmpty
                ? medium
                : subject.imageUrl,
            platform: subject.platform,
            score: subject.score,
            catalogYear: period.year,
            catalogMonth: month,
          );
        }
        offset += rows.length;
        if (offset > total) throw const FormatException('目录数量发生变化，请重新读取');
      }
      if (monthIds.length != total) throw const FormatException('目录未读取完整，请重试');
      sourceCount += total;
    }
    if (entries.length != sourceCount) {
      throw const FormatException('跨月份条目存在重复，请重新读取');
    }
    return TierCatalogResult(
      entries: sortTierPrintEntries(entries.values, TierPrintSort.date),
      sourceCount: sourceCount,
      fetchedAt: DateTime.now().toUtc(),
    );
  }
}
