import 'dart:math';

class FriendGroups {
  FriendGroups({
    Map<String, String> names = const {},
    Map<String, String> members = const {},
  }) : names = Map.unmodifiable(names),
       members = Map.unmodifiable(members);
  final Map<String, String> names, members;
  Map<String, dynamic> toJson() => {'names': names, 'members': members};
  factory FriendGroups.fromJson(Map<String, dynamic> json) {
    final names = json['names'], members = json['members'];
    if (names is! Map ||
        members is! Map ||
        names.length > 100 ||
        members.length > 5000) {
      throw const FormatException('好友分组数据无效');
    }
    final n = <String, String>{}, m = <String, String>{};
    for (final e in names.entries) {
      if (e.key is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(e.key) ||
          e.value is! String ||
          (e.value as String).trim().isEmpty ||
          (e.value as String).length > 24 ||
          n.values.contains(e.value)) {
        throw const FormatException('好友分组数据无效');
      }
      n[e.key] = e.value;
    }
    for (final e in members.entries) {
      if (e.key is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(e.key) ||
          e.value is! String ||
          !n.containsKey(e.value)) {
        throw const FormatException('好友分组数据无效');
      }
      m[(e.key as String).toLowerCase()] = e.value;
    }
    return FriendGroups(names: n, members: m);
  }
  FriendGroups rename(String? id, String name) {
    name = name.trim();
    if (name.isEmpty || name.length > 24) {
      throw const FormatException('分组名需为 1–24 个字符');
    }
    if (names.entries.any(
      (e) => e.key != id && e.value.toLowerCase() == name.toLowerCase(),
    )) {
      throw const FormatException('分组名已存在');
    }
    if (id == null && names.length >= 100) {
      throw const FormatException('最多创建 100 个分组');
    }
    if (id != null && !names.containsKey(id)) {
      throw const FormatException('分组已不存在');
    }
    id ??= List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return FriendGroups(names: {...names, id: name}, members: members);
  }

  FriendGroups remove(String id) => FriendGroups(
    names: {...names}..remove(id),
    members: {...members}..removeWhere((_, group) => group == id),
  );
  FriendGroups assign(String username, String? id) {
    if (id != null && !names.containsKey(id)) {
      throw const FormatException('分组已不存在');
    }
    final next = {...members}..remove(username.toLowerCase());
    if (id != null) next[username.toLowerCase()] = id;
    return FriendGroups.fromJson(
      FriendGroups(names: names, members: next).toJson(),
    );
  }

  FriendGroups merge(FriendGroups incoming) {
    var result = this;
    final mapped = <String, String>{};
    for (final e in incoming.names.entries) {
      var id = result.names.entries
          .where((n) => n.value.toLowerCase() == e.value.toLowerCase())
          .firstOrNull
          ?.key;
      if (id == null) {
        final old = result.names.keys.toSet();
        result = result.rename(null, e.value);
        id = result.names.keys.firstWhere((k) => !old.contains(k));
      }
      mapped[e.key] = id;
    }
    final members = {...result.members};
    for (final e in incoming.members.entries) {
      members.putIfAbsent(e.key, () => mapped[e.value]!);
    }
    return FriendGroups.fromJson(
      FriendGroups(names: result.names, members: members).toJson(),
    );
  }
}
