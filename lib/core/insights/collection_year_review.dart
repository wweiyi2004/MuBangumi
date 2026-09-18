import '../../models/bangumi_models.dart';
import 'collection_insights.dart';

enum CollectionMemoryOrder {
  highest('评分优先'),
  newest('最近更新'),
  oldest('最早更新');

  const CollectionMemoryOrder(this.label);
  final String label;
}

/// Sorts a copy, keeping the session's collection order untouched.
List<UserCollection> collectionMemories(
  Iterable<UserCollection> source, {
  CollectionMemoryOrder order = CollectionMemoryOrder.highest,
  String query = '',
}) {
  final needle = query.trim().toLowerCase();
  final items = source
      .where(
        (item) =>
            needle.isEmpty ||
            [
              item.subject.name,
              item.subject.nameCn,
              item.comment,
              ...item.tags,
            ].any((text) => text.toLowerCase().contains(needle)),
      )
      .toList();
  items.sort((a, b) {
    if (order == CollectionMemoryOrder.highest) {
      final score = (CollectionStatistics.isRated(b) ? b.rate : 0).compareTo(
        CollectionStatistics.isRated(a) ? a.rate : 0,
      );
      if (score != 0) return score;
    }
    // Missing dates always follow dated records, including ascending order.
    if (a.updatedAt == null && b.updatedAt != null) return 1;
    if (b.updatedAt == null && a.updatedAt != null) return -1;
    final date = a.updatedAt == null ? 0 : a.updatedAt!.compareTo(b.updatedAt!);
    if (date != 0) return order == CollectionMemoryOrder.oldest ? date : -date;
    return a.subjectId.compareTo(b.subjectId);
  });
  return items;
}

/// This is a view of the latest collection snapshot, not a watch-history log.
class CollectionYearReview {
  CollectionYearReview(List<UserCollection> collections, this.year) {
    items = collectionMemories(
      collections.where((item) => item.updatedAt?.toLocal().year == year),
    );
    statistics = CollectionStatistics(items);
    months = [
      for (var month = 1; month <= 12; month++)
        items.where((item) => item.updatedAt!.toLocal().month == month).length,
    ];
  }

  final int year;
  late final List<UserCollection> items;
  late final CollectionStatistics statistics;
  late final List<int> months;
  int get activeMonths => months.where((count) => count > 0).length;
  List<int> get peakMonths {
    final maxCount = months.fold<int>(0, (a, b) => a > b ? a : b);
    return maxCount == 0
        ? []
        : [
            for (var i = 0; i < months.length; i++)
              if (months[i] == maxCount) i + 1,
          ];
  }

  List<UserCollection> forMonth(int? month) => month == null
      ? items
      : items
            .where((item) => item.updatedAt!.toLocal().month == month)
            .toList();
}
