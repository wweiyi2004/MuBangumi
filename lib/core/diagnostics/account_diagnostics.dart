import 'dart:collection';
import 'dart:convert';

enum AccountArea { website, privateMessages, communityApi, communityWebsite }

enum AccountEvent {
  requestStarted,
  requestSucceeded,
  requestFailed,
  credentialRefresh,
  requestDiscarded,
  stateChanged,
  accountChanged,
  storageReadFailed,
  storageReadSucceeded,
  sessionRejected,
  loginOpened,
  browserStarting,
  browserReady,
  browserFailed,
  browserTimeout,
}

enum AccountMethod { get, post, put, patch, delete, other }

/// A bounded, process-local record. Callers cannot pass a URL, account, error
/// message, header, cookie or message body to the recording API.
class AccountDiagnostics {
  AccountDiagnostics({this.capacity = 100, DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final int capacity;
  final DateTime Function() _now;
  final _events = Queue<Map<String, Object>>();
  int _sequence = 0;
  int? webViewMajor;
  int nextRequest() => ++_sequence;
  void record(
    AccountArea area,
    AccountEvent event, {
    AccountMethod? method,
    int? request,
    int? generation,
    int? status,
    int? elapsedMs,
    int? state,
    int? attempt,
  }) {
    if (capacity <= 0) return;
    _events.add(
      Map.unmodifiable({
        'at': _now().toUtc().toIso8601String(),
        'area': area.name,
        'event': event.name,
        if (method != null) 'method': method.name,
        'request': ?request,
        'generation': ?generation,
        'http_status': ?status,
        'elapsed_ms': ?elapsedMs,
        'state': ?state,
        'attempt': ?attempt,
      }),
    );
    while (_events.length > capacity) {
      _events.removeFirst();
    }
  }

  void observeBrowser(String? userAgent) {
    webViewMajor = int.tryParse(
      RegExp(
            r'(?:Chrome|Version)/(\d{1,4})',
          ).firstMatch(userAgent ?? '')?.group(1) ??
          '',
    );
  }

  void clear() {
    _events.clear();
    webViewMajor = null;
  }

  List<Map<String, Object>> get events => List.unmodifiable(_events);
  String exportJson({
    required String platform,
    required String version,
    required String build,
    int? patch,
    required bool apiSignedIn,
    required int websiteState,
  }) => const JsonEncoder.withIndent('  ').convert({
    'schema': 1,
    'app': 'MuBangumi',
    'created_at': _now().toUtc().toIso8601String(),
    'platform':
        const {
          'android',
          'ios',
          'windows',
          'macos',
          'linux',
          'web',
        }.contains(platform)
        ? platform
        : 'unknown',
    'version': RegExp(r'^\d{1,6}(?:\.\d{1,6}){1,3}$').hasMatch(version)
        ? version
        : 'unknown',
    'build': RegExp(r'^\d{1,10}$').hasMatch(build) ? build : 'unknown',
    'patch': patch,
    'webview_major': webViewMajor,
    'api_signed_in': apiSignedIn,
    'website_state': websiteState,
    'events': events,
  });
}
