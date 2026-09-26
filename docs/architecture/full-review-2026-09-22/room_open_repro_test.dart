import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/anime_appreciation/room_storage.dart';

class EmptyVault implements RoomSecretVault {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

void main() {
  test(
    'review: room storage can retry a transient database-path failure',
    () async {
      var attempts = 0;
      final storage = RoomLocalStorage(
        vault: EmptyVault(),
        databasePath: () async {
          attempts++;
          if (attempts == 1) {
            throw StateError('temporary directory unavailable');
          }
          return ':memory:';
        },
      );
      await expectLater(storage.read(), throwsStateError);
      expect(
        await storage.read(),
        isNull,
        reason:
            'Once the path provider recovers, reading an empty room database should succeed.',
      );
      expect(attempts, 2);
    },
  );
}
