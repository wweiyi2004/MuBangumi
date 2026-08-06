import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../state/rss_controller.dart';
import '../../state/schedule_controller.dart';
import 'home_widget_bridge.dart';

/// Listens to schedule/RSS and keeps the Android home widget in sync.
/// Also reports widget taps via [onOpenSchedule].
class HomeWidgetSyncHost extends ConsumerStatefulWidget {
  const HomeWidgetSyncHost({
    super.key,
    required this.child,
    this.onOpenSchedule,
  });

  final Widget child;
  final VoidCallback? onOpenSchedule;

  @override
  ConsumerState<HomeWidgetSyncHost> createState() => _HomeWidgetSyncHostState();
}

class _HomeWidgetSyncHostState extends ConsumerState<HomeWidgetSyncHost> {
  StreamSubscription<Uri?>? _clickSub;
  var _syncQueued = false;

  @override
  void initState() {
    super.initState();
    if (!HomeWidgetBridge.isSupported) return;
    unawaited(_bindClicks());
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNow());
  }

  Future<void> _bindClicks() async {
    try {
      final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initial != null && mounted) {
        widget.onOpenSchedule?.call();
      }
      _clickSub = HomeWidget.widgetClicked.listen((uri) {
        if (uri == null) return;
        widget.onOpenSchedule?.call();
      });
    } catch (_) {}
  }

  void _queueSync() {
    if (_syncQueued || !HomeWidgetBridge.isSupported) return;
    _syncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncQueued = false;
      _syncNow();
    });
  }

  Future<void> _syncNow() async {
    if (!HomeWidgetBridge.isSupported || !mounted) return;
    final schedule = ref.read(scheduleProvider).schedule;
    final rss = ref.read(rssProvider);
    await HomeWidgetBridge.sync(
      schedule: schedule,
      unreadBySubject: rss.unreadBySubject,
      totalUnread: rss.totalUnread,
    );
  }

  @override
  void dispose() {
    _clickSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (HomeWidgetBridge.isSupported) {
      ref.listen(scheduleProvider, (previous, next) {
        if (previous?.schedule != next.schedule ||
            previous?.loading != next.loading) {
          _queueSync();
        }
      });
      ref.listen(rssProvider, (previous, next) {
        if (previous?.totalUnread != next.totalUnread ||
            previous?.unreadBySubject != next.unreadBySubject ||
            previous?.loaded != next.loaded) {
          _queueSync();
        }
      });
    }
    return widget.child;
  }
}
