import '../../models/bangumi_models.dart';
import 'collection_insights.dart';

/// This is a view of the latest collection snapshot, not a watch-history log.
class CollectionYearReview {
  CollectionYearReview(List<UserCollection> collections, this.year) {
    items =
        collections
            .where((item) => item.updatedAt?.toLocal().year == year)
            .toList()
          ..sort((a, b) {
            final score = b.rate.compareTo(a.rate);
            return score != 0 ? score : b.updatedAt!.compareTo(a.updatedAt!);
          });
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
