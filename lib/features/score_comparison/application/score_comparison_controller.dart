import 'package:flutter/foundation.dart';
import '../../../models/bangumi_models.dart';
import '../../../models/netaba_models.dart';

class ComparisonEntry {
  const ComparisonEntry({
    required this.subject,
    this.history,
    this.loading = false,
    this.error,
  });
  final Subject subject;
  final NetabaSubjectHistory? history;
  final bool loading;
  final String? error;
}

class ScoreComparisonController extends ChangeNotifier {
  ScoreComparisonController(this.loadHistory);
  final Future<NetabaSubjectHistory> Function(int) loadHistory;
  static const limit = 6;
  final Map<int, ComparisonEntry> _entries = {};
  final Map<int, int> _requests = {};
  bool _disposed = false;
  int _generation = 0;
  List<ComparisonEntry> get entries => _entries.values.toList(growable: false);
  Future<void> add(Subject subject) async {
    if (_disposed ||
        _entries.containsKey(subject.id) ||
        _entries.length >= limit) {
      return;
    }
    _entries[subject.id] = ComparisonEntry(subject: subject);
    await reload(subject.id);
  }

  Future<void> reload(int id) async {
    final entry = _entries[id];
    if (_disposed || entry == null) return;
    final generation = _generation;
    final request = _requests[id] = (_requests[id] ?? 0) + 1;
    _entries[id] = ComparisonEntry(
      subject: entry.subject,
      history: entry.history,
      loading: true,
    );
    notifyListeners();
    try {
      final history = await loadHistory(id);
      if (_disposed ||
          generation != _generation ||
          request != _requests[id] ||
          !_entries.containsKey(id)) {
        return;
      }
      _entries[id] = ComparisonEntry(subject: entry.subject, history: history);
    } catch (error) {
      if (_disposed ||
          generation != _generation ||
          request != _requests[id] ||
          !_entries.containsKey(id)) {
        return;
      }
      final text = error.toString();
      _entries[id] = ComparisonEntry(
        subject: entry.subject,
        history: entry.history,
        error: text.contains('暂无历史') || text.contains('404')
            ? '数据源尚未收录此作品的历史评分'
            : '历史评分加载失败，请重试',
      );
    }
    notifyListeners();
  }

  void remove(int id) {
    _entries.remove(id);
    _requests[id] = (_requests[id] ?? 0) + 1;
    notifyListeners();
  }

  void reset() {
    _generation++;
    _entries.clear();
    _requests.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
