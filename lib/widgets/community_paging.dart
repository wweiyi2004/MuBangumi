import 'package:flutter/widgets.dart';

/// Load-more state shared by the community list screens.
///
/// Screens own request ids / generations and call `setState`; this only holds
/// the flags and the scroll trigger so every list agrees on when to append.
class CommunityPaging {
  CommunityPaging({this.loading = false});

  bool loading;
  bool loadingMore = false;
  bool hasMore = true;

  /// Error of the last append. Single-list screens that share one footer also
  /// keep the last refresh error here; [refreshFailed] then selects the retry.
  String? loadMoreError;
  bool refreshFailed = false;

  bool get canLoadMore => !loading && !loadingMore && hasMore;

  /// Starts a (re)load and clears any append state.
  void begin() {
    loading = true;
    loadingMore = false;
    loadMoreError = null;
    refreshFailed = false;
  }

  void beginLoadMore() {
    loadingMore = true;
    loadMoreError = null;
  }

  /// Forgets everything about the previous list without touching [loading].
  void reset() {
    hasMore = true;
    loadMoreError = null;
    loadingMore = false;
    refreshFailed = false;
  }

  bool shouldLoadMore(ScrollMetrics metrics, {required double threshold}) =>
      loadMoreError == null && metrics.extentAfter < threshold;

  /// For a parent [NotificationListener] driving a nested primary scrollable.
  bool shouldLoadMoreOnNotification(
    ScrollNotification notification, {
    required double threshold,
  }) =>
      notification.depth == 0 &&
      notification is ScrollUpdateNotification &&
      notification.metrics.axis == Axis.vertical &&
      shouldLoadMore(notification.metrics, threshold: threshold);
}
