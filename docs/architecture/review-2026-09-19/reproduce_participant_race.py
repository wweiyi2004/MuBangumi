from pathlib import Path
p=Path('test/banjian_participation_test.dart').read_text(encoding='utf-8')
p="import 'dart:async';\n"+p
cases="""
  test('architecture audit: older HTTP success cannot undo a newer refresh', () async {
    final held = HeldStateApi(c.api!);
    c.api = held;
    final oldRequest = c.refresh();
    final oldSnapshot = await held.captured.future;
    admin('rename', {'title': '较新的活动状态'});
    await c.refresh();
    expect(c.event?['title'], '较新的活动状态');
    held.release.complete(oldSnapshot);
    await oldRequest;
    expect(c.event?['title'], '较新的活动状态', reason: 'late snapshot must not roll back current event');
  });
  test('architecture audit: older HTTP failure cannot disconnect a newer success', () async {
    final held = HeldStateApi(c.api!);
    c.api = held;
    final oldRequest = c.refresh();
    await held.captured.future;
    await c.refresh();
    expect(c.online, true);
    held.release.completeError(StateError('simulated late network failure'));
    await oldRequest;
    expect(c.online, true, reason: 'late failure must not overwrite successful connection state');
  });
"""
p=p.replace("  test('leave hides temporary entry and rejoin keeps one identity',",cases+"\n  test('leave hides temporary entry and rejoin keeps one identity',")
p+="""
class HeldStateApi extends RoomApi {
  HeldStateApi(this.delegate):super(delegate.base, token:delegate.token);
  final RoomApi delegate;
  final captured = Completer<Json>();
  final release = Completer<Json>();
  var count = 0;
  @override
  Future<Json> request(String path, [Json? body]) async {
    if (path.startsWith('state?') && count++ == 0) {
      captured.complete(await delegate.request(path,body));
      return release.future;
    }
    return delegate.request(path,body);
  }
}
"""
Path('.dart_tool/architecture_race_repro_test.dart').write_text(p,encoding='utf-8')
