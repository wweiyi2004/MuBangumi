import 'package:mubangumi/core/storage/browsing_store.dart';

class MemoryHomePins implements HomePinsRepository {
  final data = <int, List<int>>{};
  bool failRead = false, failSave = false;
  Future<List<int>>? pendingRead;
  Future<void>? pendingSave;
  int writes = 0;
  @override
  Future<List<int>> readHomePins(int ownerId) async {
    if (failRead) throw StateError('read failed');
    return pendingRead ?? List<int>.from(data[ownerId] ?? const []);
  }

  @override
  Future<void> saveHomePins(int ownerId, List<int> ids) async {
    writes++;
    await pendingSave;
    if (failSave) throw StateError('save failed');
    data[ownerId] = List.from(ids);
  }
}
