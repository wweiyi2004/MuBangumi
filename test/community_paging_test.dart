import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/community_paging.dart';

FixedScrollMetrics _metrics({
  required double pixels,
  double max = 1000,
  Axis axis = Axis.vertical,
}) => FixedScrollMetrics(
  minScrollExtent: 0,
  maxScrollExtent: max,
  pixels: pixels,
  viewportDimension: 600,
  axisDirection: axis == Axis.vertical
      ? AxisDirection.down
      : AxisDirection.right,
  devicePixelRatio: 1,
);

void main() {
  test('begin clears append state and marks loading', () {
    final paging = CommunityPaging()
      ..loadingMore = true
      ..loadMoreError = 'boom'
      ..refreshFailed = true;
    paging.begin();
    expect(paging.loading, isTrue);
    expect(paging.loadingMore, isFalse);
    expect(paging.loadMoreError, isNull);
    expect(paging.refreshFailed, isFalse);
  });

  test('canLoadMore requires idle and remaining pages', () {
    final paging = CommunityPaging();
    expect(paging.canLoadMore, isTrue);
    paging.loading = true;
    expect(paging.canLoadMore, isFalse);
    paging.loading = false;
    paging.beginLoadMore();
    expect(paging.canLoadMore, isFalse);
    paging.loadingMore = false;
    paging.hasMore = false;
    expect(paging.canLoadMore, isFalse);
  });

  test('reset keeps loading but restores paging defaults', () {
    final paging = CommunityPaging(loading: true)
      ..hasMore = false
      ..loadingMore = true
      ..loadMoreError = 'x'
      ..refreshFailed = true;
    paging.reset();
    expect(paging.loading, isTrue);
    expect(paging.hasMore, isTrue);
    expect(paging.loadingMore, isFalse);
    expect(paging.loadMoreError, isNull);
    expect(paging.refreshFailed, isFalse);
  });

  test('shouldLoadMore honours the explicit threshold and error latch', () {
    final paging = CommunityPaging();
    // extentAfter = 1000 - 450 = 550
    final metrics = _metrics(pixels: 450);
    expect(paging.shouldLoadMore(metrics, threshold: 500), isFalse);
    expect(paging.shouldLoadMore(metrics, threshold: 600), isTrue);
    expect(
      paging.shouldLoadMore(_metrics(pixels: 501), threshold: 500),
      isTrue,
    );
    paging.loadMoreError = 'failed';
    expect(
      paging.shouldLoadMore(_metrics(pixels: 900), threshold: 500),
      isFalse,
    );
  });

  test('notification trigger only accepts vertical root updates', () {
    final paging = CommunityPaging();
    final context = _FakeContext();
    ScrollUpdateNotification update(ScrollMetrics m, {int depth = 0}) =>
        ScrollUpdateNotification(metrics: m, context: context, depth: depth);
    expect(
      paging.shouldLoadMoreOnNotification(
        update(_metrics(pixels: 900)),
        threshold: 400,
      ),
      isTrue,
    );
    expect(
      paging.shouldLoadMoreOnNotification(
        update(_metrics(pixels: 900), depth: 1),
        threshold: 400,
      ),
      isFalse,
    );
    expect(
      paging.shouldLoadMoreOnNotification(
        update(_metrics(pixels: 900, axis: Axis.horizontal)),
        threshold: 400,
      ),
      isFalse,
    );
    expect(
      paging.shouldLoadMoreOnNotification(
        ScrollStartNotification(
          metrics: _metrics(pixels: 900),
          context: context,
        ),
        threshold: 400,
      ),
      isFalse,
    );
  });
}

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
