import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Available means a network interface exists, not that Bangumi is reachable.
enum NetworkAvailability { unknown, unavailable, available }

abstract interface class NetworkMonitor {
  Future<NetworkAvailability> check();
  Stream<NetworkAvailability> get changes;
}

class PlatformNetworkMonitor implements NetworkMonitor {
  final _connectivity = Connectivity();
  NetworkAvailability _status(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none)
      ? NetworkAvailability.available
      : NetworkAvailability.unavailable;

  @override
  Future<NetworkAvailability> check() async =>
      _status(await _connectivity.checkConnectivity());

  @override
  Stream<NetworkAvailability> get changes =>
      _connectivity.onConnectivityChanged.map(_status);
}

final networkMonitorProvider = Provider<NetworkMonitor>(
  (ref) => PlatformNetworkMonitor(),
);
final networkStatusProvider =
    StateNotifierProvider<NetworkStatusController, NetworkAvailability>(
      (ref) => NetworkStatusController(ref.watch(networkMonitorProvider)),
    );

class NetworkStatusController extends StateNotifier<NetworkAvailability> {
  NetworkStatusController(this._monitor) : super(NetworkAvailability.unknown) {
    try {
      _subscription = _monitor.changes.listen(
        (value) {
          _version++;
          if (mounted) state = value;
        },
        onError: (Object _) {
          _version++;
          if (mounted) state = NetworkAvailability.unknown;
        },
      );
    } catch (_) {
      // Unsupported/test platforms keep the existing request-based behavior.
    }
    unawaited(refresh());
  }

  final NetworkMonitor _monitor;
  StreamSubscription<NetworkAvailability>? _subscription;
  int _version = 0;

  Future<void> refresh() async {
    if (!mounted) return;
    final version = ++_version;
    try {
      final value = await _monitor.check();
      if (mounted && version == _version) state = value;
    } catch (_) {
      if (mounted && version == _version) state = NetworkAvailability.unknown;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
