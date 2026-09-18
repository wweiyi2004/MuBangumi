import 'dart:async';

/// Coalesces noisy interface events and serializes recovery across reconnects.
/// The supplied action owns account guards and ordinary request error handling.
class NetworkRecoveryController {
  NetworkRecoveryController({
    required this.recover,
    this.delay = const Duration(milliseconds: 600),
  });
  final Future<void> Function() recover;
  final Duration delay;
  Timer? _timer;
  bool _running = false;
  bool _requested = false;
  bool _available = false;
  bool _foreground = true;
  bool _disposed = false;
  bool get isRunning => _running;

  void setAvailable(bool value) {
    _available = value;
    if (!value) {
      _timer?.cancel();
      _timer = null;
      _requested = false;
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    if (!value) {
      _timer?.cancel();
      _timer = null;
    } else if (_requested) {
      request();
    }
  }

  void request() {
    if (_disposed || !_available) return;
    _requested = true;
    if (_running || !_foreground || _timer != null) return;
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_disposed || !_available || !_foreground) return;
    _requested = false;
    _running = true;
    try {
      await recover();
    } catch (_) {
      // A connected interface can still have no Internet access. Normal sync
      // retry and the cached-data notice remain responsible for that failure.
    } finally {
      _running = false;
      if (_requested) request();
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
