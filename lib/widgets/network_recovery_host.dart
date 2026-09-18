import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/sync/application/network_recovery_controller.dart';
import '../state/network_status_controller.dart';
import '../state/session_controller.dart';
import 'offline_status_banner.dart';

class NetworkRecoveryHost extends ConsumerStatefulWidget {
  const NetworkRecoveryHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<NetworkRecoveryHost> createState() =>
      _NetworkRecoveryHostState();
}

class _NetworkRecoveryHostState extends ConsumerState<NetworkRecoveryHost> {
  late final NetworkRecoveryController _recovery;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _recovery = NetworkRecoveryController(
      recover: () async {
        if (!mounted) return;
        final session = ref.read(sessionProvider);
        if (session.phase != SessionPhase.signedIn ||
            session.isAuthenticating) {
          return;
        }
        // refresh captures the current account before flushing its queue, and
        // checks it again before reading or publishing remote collections.
        await ref.read(sessionProvider.notifier).refresh(showIndicator: false);
      },
    );
    _recovery.setAvailable(
      ref.read(networkStatusProvider) == NetworkAvailability.available,
    );
    ref.listenManual(networkStatusProvider, (previous, next) {
      _recovery.setAvailable(next == NetworkAvailability.available);
      if (next == NetworkAvailability.available && previous != next) {
        final session = ref.read(sessionProvider);
        if (previous == NetworkAvailability.unavailable ||
            (session.isUsingCachedCollections &&
                !session.isLoadingCollections)) {
          _recovery.request();
        }
      }
    });
    ref.listenManual(sessionProvider, (previous, next) {
      // Covers a cold offline restore whose network check arrived before the
      // saved login did, and a new account that joined an old recovery request.
      if (next.phase == SessionPhase.signedIn &&
          next.isUsingCachedCollections &&
          !next.isLoadingCollections &&
          (previous?.user?.id != next.user?.id ||
              (previous?.isLoadingCollections == true &&
                  !_recovery.isRunning))) {
        _recovery.request();
      }
    });
    final current = WidgetsBinding.instance.lifecycleState;
    _recovery.setForeground(
      current == null || current == AppLifecycleState.resumed,
    );
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _recovery.setForeground(state == AppLifecycleState.resumed);
        if (state == AppLifecycleState.resumed) {
          unawaited(_resume());
        }
      },
    );
  }

  Future<void> _resume() async {
    await ref.read(networkStatusProvider.notifier).refresh();
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    if (session.isUsingCachedCollections || session.pendingSyncCount > 0) {
      _recovery.request();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _recovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const OfflineStatusBanner(),
      Expanded(
        child: MediaQuery.removePadding(
          context: context,
          removeTop: ref.watch(offlineNoticeVisibleProvider),
          child: widget.child,
        ),
      ),
    ],
  );
}
