import 'dart:async';

/// Run tasks in order while keeping each failure visible to its caller.
class SerialTaskQueue {
  Future<void>? _tail;

  Future<void> get done => _tail ?? Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final settled = Completer<void>();
    final ticket = settled.future;
    // Reserve the slot before invoking action, including reentrant enqueues.
    _tail = ticket;
    final next = previous == null
        ? Future<T>.microtask(action)
        : previous.then((_) => action());
    void release() {
      // A completed tail need not retain the previous operation's async zone.
      if (identical(_tail, ticket)) _tail = null;
      settled.complete();
    }

    next.then<void>(
      (_) => release(),
      onError: (Object _, StackTrace _) => release(),
    );
    return next;
  }
}
