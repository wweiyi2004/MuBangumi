import 'dart:io';
import 'protocol.dart';

/// Suggestions based on interface names and address scope, not a claim that
/// another device has passed a reachability test.
class RoomShareAddress {
  RoomShareAddress(this.interfaceName, this.uri);
  final String interfaceName;
  final Uri uri;
  bool get privateLan => isPrivateLanHost(uri.host);
  bool get virtual => RegExp(
    r'vmware|vmnet|virtual|vbox|vethernet|docker|wsl|tailscale|tun\d|tap\d|vpn|utun|zerotier',
    caseSensitive: false,
  ).hasMatch(interfaceName);
  bool get hotspot =>
      !virtual &&
      (RegExp(
            r'^(ap\d|swlan\d)|hotspot|wi-fi direct|热点|本地连接\*',
            caseSensitive: false,
          ).hasMatch(interfaceName) ||
          uri.host == '192.168.137.1');
  bool get wifi =>
      !virtual &&
      RegExp(
        r'wlan|wi-?fi|wireless|无线',
        caseSensitive: false,
      ).hasMatch(interfaceName);
  bool get ethernet =>
      !virtual &&
      RegExp(
        r'ethernet|以太网|^eth\d|^en\d|^enp',
        caseSensitive: false,
      ).hasMatch(interfaceName);
  bool get loopback => uri.host == 'localhost' || uri.host.startsWith('127.');
  int get priority => loopback
      ? -100
      : !privateLan
      ? -50
      : virtual
      ? 0
      : hotspot
      ? 100
      : wifi
      ? 90
      : ethernet
      ? 70
      : 40;
  String get kind => loopback
      ? '仅本机'
      : virtual
      ? '虚拟网络'
      : hotspot
      ? '热点 / 共享网络'
      : wifi
      ? 'Wi-Fi'
      : ethernet
      ? '有线网络'
      : privateLan
      ? '局域网'
      : '不可用于普通局域网分享';
  String get label => '$kind · $interfaceName';
  String get address => uri.origin;
}

List<RoomShareAddress> rankRoomAddresses(Iterable<RoomShareAddress> values) {
  final unique = <String, RoomShareAddress>{};
  for (final value in values) {
    final previous = unique[value.uri.origin];
    if (previous == null || previous.priority < value.priority)
      unique[value.uri.origin] = value;
  }
  return unique.values.toList()..sort((a, b) {
    final order = b.priority.compareTo(a.priority);
    return order != 0 ? order : a.address.compareTo(b.address);
  });
}

Future<List<RoomShareAddress>> listRoomAddresses(int port) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  return rankRoomAddresses([
    for (final interface in interfaces)
      for (final address in interface.addresses)
        if (!address.isLoopback)
          RoomShareAddress(
            interface.name,
            Uri(scheme: 'http', host: address.address, port: port),
          ),
  ]);
}
