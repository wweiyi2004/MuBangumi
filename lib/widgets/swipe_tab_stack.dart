import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Keeps visited pages and scroll offsets while allowing animated navigation.
class SwipeTabStack extends StatefulWidget {
  const SwipeTabStack({
    super.key,
    required this.index,
    required this.onChanged,
    required this.children,
    this.onPreview,
  });
  final int index;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onPreview;
  final List<Widget> children;
  @override
  State<SwipeTabStack> createState() => _SwipeTabStackState();
}

class _SwipeTabStackState extends State<SwipeTabStack> {
  late final _controller = PageController(initialPage: widget.index);
  bool _animating = false;
  int _animation = 0;
  int? _reportedPage;
  @override
  void didUpdateWidget(covariant SwipeTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_reportedPage == widget.index) {
      _reportedPage = null;
      return;
    }
    if (widget.index != oldWidget.index &&
        _controller.hasClients &&
        (_controller.page! - widget.index).abs() > .01) {
      final animation = ++_animation;
      _animating = true;
      _controller
          .animateToPage(
            widget.index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted && animation == _animation) {
              _animating = false;
              // A user drag interrupting a navigation animation owns the final page.
              final page = _controller.page?.round();
              if (page != null && page != widget.index) widget.onChanged(page);
            }
          });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      },
    ),
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0 || !_controller.hasClients) return false;
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null &&
            _animating) {
          _animation++;
          _animating = false;
        }
        if (!_animating && notification is ScrollUpdateNotification) {
          final page = _controller.page!;
          widget.onPreview?.call(
            (page > widget.index ? page.ceil() : page.floor()).clamp(
              0,
              widget.children.length - 1,
            ),
          );
        }
        if (!_animating && notification is ScrollEndNotification) {
          final page = _controller.page!.round();
          if (page != widget.index) {
            _reportedPage = page;
            widget.onChanged(page);
          }
        }
        return false;
      },
      child: PageView.builder(
        key: const ValueKey('main-swipe-pages'),
        controller: _controller,
        onPageChanged: (index) {
          if (!_animating && index != widget.index) {
            _reportedPage = index;
            widget.onChanged(index);
          }
        },
        itemCount: widget.children.length,
        itemBuilder: (context, index) => _RetainedPage(
          key: ValueKey(index),
          child: TickerMode(
            enabled: index == widget.index,
            child: widget.children[index],
          ),
        ),
      ),
    ),
  );
}

class _RetainedPage extends StatefulWidget {
  const _RetainedPage({super.key, required this.child});
  final Widget child;
  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
