import 'dart:io';
import 'package:banjian_server/banjian_server.dart';

/// Local maintenance: enrich only missing artwork in existing active rooms.
/// No event creation, votes, comments, membership or round changes.
Future<void> main(List<String> args) async {
  if (args.length != 1 || !File(args.single).existsSync()) {
    stderr.writeln(
      'Usage: dart run tool/maintenance/repair_banjian_covers.dart <existing-database>',
    );
    exitCode = 64;
    return;
  }
  final store = RoomStore(args.single);
  final service = RoomServer(
    store: store,
    adminPassword: newSecret(),
    assets: {},
    autoCacheCovers: false,
  );
  try {
    for (final event in store.history().where((e) => e['ended'] != true)) {
      await service.repairCovers(event['id']);
      final rounds = store.event(event['id'])['rounds'] as List;
      final ready = rounds
          .where(
            (r) => service.coverCache.contains(
              r['subject']['cover'] as String? ?? '',
            ),
          )
          .length;
      stdout.writeln('Cached covers: $ready / ${rounds.length}');
    }
  } finally {
    await service.close();
    store.close();
  }
}
