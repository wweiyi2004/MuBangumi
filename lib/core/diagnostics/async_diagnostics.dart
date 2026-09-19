import 'dart:collection';

enum AsyncEvent {
  readStarted,
  readAccepted,
  readSuperseded,
  readFailed,
  invalidPayload,
  commandConfirmed,
  commandPending,
}

/// In-memory, bounded diagnostics. The API accepts only numeric correlation
/// fields, never credentials, URLs, names or message bodies.
class AsyncDiagnostics {
  AsyncDiagnostics({this.capacity = 64});
  final int capacity;
  final _events = Queue<Map<String, Object>>();
  void record(
    AsyncEvent event, {
    int? request,
    int? generation,
    int? revision,
    int? elapsedMs,
    int? status,
    int? pending,
  }) {
    if (capacity <= 0) return;
    _events.add(
      Map.unmodifiable({
        'event': event.name,
        'at': DateTime.now().toUtc().toIso8601String(),
        'request': ?request,
        'generation': ?generation,
        'revision': ?revision,
        'elapsed_ms': ?elapsedMs,
        'status': ?status,
        'pending': ?pending,
      }),
    );
    while (_events.length > capacity) {
      _events.removeFirst();
    }
  }

  List<Map<String, Object>> get events => List.unmodifiable(_events);
}
