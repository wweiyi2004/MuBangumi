import '../backup/backup_archive.dart';

/// Accepted controller writes can outlive an auto-disposed page. A backup must
/// wait for them before taking its database snapshot, including queued writes
/// which have not reached the store yet.
class PendingPersonalWrites {
  static final _pending = <(int, BackupCategory), Set<Future<void>>>{};

  static void track(int owner, BackupCategory category, Future<void> work) {
    final key = (owner, category);
    final pending = _pending.putIfAbsent(key, () => {});
    final settled = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    pending.add(settled);
    settled.then((_) {
      pending.remove(settled);
      if (pending.isEmpty) _pending.remove(key);
    });
  }

  static Future<void> drain(int owner, Set<BackupCategory> categories) async {
    while (true) {
      final pending = [
        for (final category in categories) ...?_pending[(owner, category)],
      ];
      if (pending.isEmpty) return;
      await Future.wait(pending);
    }
  }
}
