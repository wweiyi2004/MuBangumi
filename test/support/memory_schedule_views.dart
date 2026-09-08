import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/models/schedule_view.dart';

class MemoryScheduleViews implements ScheduleViewRepository {
  final views = <int, ScheduleView>{};
  Future<ScheduleView?>? pendingRead;
  bool failSave = false;
  @override
  Future<ScheduleView?> readScheduleView(int ownerId) async =>
      pendingRead ?? views[ownerId];
  @override
  Future<void> saveScheduleView(int ownerId, ScheduleView view) async {
    if (failSave) throw StateError('disk full');
    views[ownerId] = view;
  }
}
