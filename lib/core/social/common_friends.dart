import '../../models/bangumi_models.dart';

String _friendKey(String username) => username.trim().toLowerCase();

List<BangumiUser> findCommonFriends(
  Iterable<BangumiUser> first,
  Iterable<BangumiUser> second,
) {
  final firstByUsername = <String, BangumiUser>{};
  for (final user in first) {
    final key = _friendKey(user.username);
    if (key.isNotEmpty) firstByUsername[key] = user;
  }

  final common = <BangumiUser>[];
  final seen = <String>{};
  for (final user in second) {
    final key = _friendKey(user.username);
    if (key.isEmpty || !seen.add(key)) continue;
    final match = firstByUsername[key];
    if (match != null) common.add(user);
  }
  return common;
}
