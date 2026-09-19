import 'dart:collection';

class SnapshotItems<T> extends UnmodifiableListView<T> {
  SnapshotItems(super.source, {required this.savedAt});
  final DateTime savedAt;
}
