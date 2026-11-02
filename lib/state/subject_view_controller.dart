import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SubjectView { adaptive, list, twoColumns, threeColumns }

class SubjectViewController extends StateNotifier<SubjectView> {
  SubjectViewController(this.key, this.storage) : super(SubjectView.adaptive) {
    _restore();
  }
  final String key;
  final FlutterSecureStorage storage;
  int _revision = 0;
  Future<void> _writes = Future.value();
  Future<void> _restore() async {
    final revision = _revision;
    try {
      final saved = await storage.read(key: key);
      if (mounted && revision == _revision) {
        state =
            SubjectView.values
                .where((view) => view.name == saved)
                .firstOrNull ??
            SubjectView.adaptive;
      }
    } catch (_) {
      /* An optional preference must never block content. */
    }
  }

  Future<void> select(SubjectView view) async {
    _revision++;
    state = view;
    final write = _writes.then(
      (_) => storage.write(key: key, value: view.name),
    );
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await write;
    } catch (_) {
      /* Retain the current session choice. */
    }
  }
}

final subjectViewProvider =
    StateNotifierProvider.family<SubjectViewController, SubjectView, String>(
      (ref, page) => SubjectViewController(
        'subject_view_$page',
        const FlutterSecureStorage(),
      ),
    );
