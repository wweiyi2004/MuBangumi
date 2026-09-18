import 'package:banjian_server/banjian_server.dart';
import 'dart:io';

Future<void> main() async {
  final addresses = await listRoomAddresses(43928);
  for (final address in addresses) {
    stdout.writeln('${address.priority}\t${address.label}\t${address.address}');
  }
  stdout.writeln(
    'Interface recommendation only; other-device reachability is not implied.',
  );
}
