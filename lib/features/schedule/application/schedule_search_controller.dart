import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/bangumi_api.dart';
import '../../../models/bangumi_models.dart';

/// Owns one search sheet's requests; no account or schedule writes happen here.
class ScheduleSearchController extends ChangeNotifier {
  ScheduleSearchController({required this._api});

  final BangumiApi Function() _api;
  Timer? _debounce;
  int _requestId = 0;
  int _calendarRequestId = 0;
  bool _disposed = false;
  String _query = '';
  SubjectType _type = SubjectType.anime;
  List<Subject> _results = const [];
  bool _loading = false;
  String? _error;
  bool _calendarLoading = true;
  Map<int, int> _officialDays = const {};

  SubjectType get type => _type;
  List<Subject> get results => _results;
  bool get loading => _loading;
  String? get error => _error;
  bool get calendarLoading => _calendarLoading;
  int? officialDay(int subjectId) => _officialDays[subjectId];

  void changeQuery(String value) {
    if (_disposed) return;
    _query = value.trim();
    _requestId++;
    _debounce?.cancel();
    _results = const [];
    _error = null;
    _loading = _query.isNotEmpty;
    if (_loading) {
      _debounce = Timer(const Duration(milliseconds: 400), () {
        unawaited(submit());
      });
    }
    notifyListeners();
  }

  Future<void> selectType(SubjectType value) {
    if (_disposed) return Future.value();
    _type = value;
    return submit();
  }

  Future<void> submit() async {
    if (_disposed) return;
    _debounce?.cancel();
    final request = ++_requestId;
    final keyword = _query;
    final subjectType = _type;
    _results = const [];
    _error = null;
    _loading = keyword.isNotEmpty;
    notifyListeners();
    if (keyword.isEmpty) return;
    try {
      final results = await _api().searchSubjects(
        keyword,
        subjectType: subjectType,
        limit: 20,
      );
      if (_disposed || request != _requestId) return;
      _results = List.unmodifiable(results);
      _loading = false;
      notifyListeners();
    } catch (error) {
      if (_disposed || request != _requestId) return;
      _loading = false;
      _error = error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  Future<void> loadCalendar() async {
    if (_disposed) return;
    final request = ++_calendarRequestId;
    _calendarLoading = true;
    notifyListeners();
    try {
      final days = await _api().getCalendar().timeout(
        const Duration(seconds: 8),
      );
      if (_disposed || request != _calendarRequestId) return;
      _officialDays = {
        for (final day in days)
          if (day.weekday >= 1 && day.weekday <= 7)
            for (final subject in day.subjects) subject.id: day.weekday,
      };
    } catch (_) {
      // Unavailable calendar data must not prevent manual arrangement.
    } finally {
      if (!_disposed && request == _calendarRequestId) {
        _calendarLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
