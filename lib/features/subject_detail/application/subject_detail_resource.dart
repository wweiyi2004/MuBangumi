import 'package:flutter/foundation.dart';

/// A detail section keeps its last value while a newer request is pending.
/// Only the latest request may publish, including errors and loading state.
class SubjectDetailResource<T> extends ChangeNotifier {
  SubjectDetailResource({
    required T initial,
    required this._request,
    required this._errorMessage,
  }) : _value = initial;

  final Future<T> Function() _request;
  final String Function(Object) _errorMessage;
  T _value;
  bool _loading = false;
  String? _error;
  int _generation = 0;
  int _attempts = 0;
  bool _disposed = false;

  T get value => _value;
  bool get loading => _loading;
  String? get error => _error;
  int get attempts => _attempts;
  bool get attempted => _attempts > 0;

  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_generation;
    _attempts++;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final value = await _request();
      if (_disposed || generation != _generation) return;
      _value = value;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _error = _errorMessage(error);
    }
    if (_disposed || generation != _generation) return;
    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
