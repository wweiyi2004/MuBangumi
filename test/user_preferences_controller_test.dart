import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/user_preference_store.dart';
import 'package:mubangumi/state/user_preferences_controller.dart';

void main() {
  test('local notes and blocking are normalized by username', () async {
    final repository = _MemoryPreferenceRepository();
    final controller = UserPreferencesController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    await controller.setNote('Alice', '同好');
    await controller.setBlocked('ALICE', true);

    final preference = controller.state.preferenceFor('alice');
    expect(preference.note, '同好');
    expect(preference.blocked, isTrue);
    expect(repository.items.single.username, 'alice');
  });

  test('failed persistence rolls optimistic update back', () async {
    final repository = _MemoryPreferenceRepository(failSave: true);
    final controller = UserPreferencesController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    await expectLater(controller.setBlocked('bob', true), throwsException);

    expect(controller.state.isBlocked('bob'), isFalse);
    expect(controller.state.error, isNotNull);
  });
}

class _MemoryPreferenceRepository implements UserPreferenceRepository {
  _MemoryPreferenceRepository({this.failSave = false});

  final bool failSave;
  final List<LocalUserPreference> items = [];

  @override
  Future<List<LocalUserPreference>> loadAll() async => [...items];

  @override
  Future<void> save(LocalUserPreference preference) async {
    if (failSave) throw Exception('disk full');
    items.removeWhere((item) => item.key == preference.key);
    items.add(preference);
  }
}
