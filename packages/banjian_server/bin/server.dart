import 'dart:io';
import 'package:banjian_server/banjian_server.dart';

Future<void> main() async {
  final env = Platform.environment;
  final password = env['BANJIAN_ADMIN_PASSWORD'] ?? '';
  if (password.length < 12) {
    stderr.writeln('Set BANJIAN_ADMIN_PASSWORD (at least 12 characters).');
    exitCode = 64;
    return;
  }
  final directory = Directory(env['BANJIAN_DATA'] ?? './data')
    ..createSync(recursive: true);
  final web = Directory(env['BANJIAN_WEB'] ?? './web');
  final assets = <String, List<int>>{};
  for (final name in ['index.html', 'app.css', 'app.js']) {
    assets[name] = await File('${web.path}/$name').readAsBytes();
  }
  final store = RoomStore('${directory.path}/banjian.sqlite');
  final server = RoomServer(
    store: store,
    adminPassword: password,
    assets: assets,
    publicOrigin: env['BANJIAN_PUBLIC_ORIGIN'],
  );
  await server.start(
    port: int.parse(env['PORT'] ?? '43928'),
    address: InternetAddress(env['BANJIAN_BIND'] ?? '0.0.0.0'),
  );
  stdout.writeln('BanJian listening on ${server.port}; open /admin.');
  var closing = false;
  Future<void> stop(ProcessSignal _) async {
    if (closing) return;
    closing = true;
    await server.close();
    store.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(stop);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(stop);
}
