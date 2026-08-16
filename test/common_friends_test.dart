import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/social/common_friends.dart';
import 'package:mubangumi/models/bangumi_models.dart';

BangumiUser _user(String username, {String nickname = ''}) => BangumiUser(
  id: username.hashCode,
  username: username,
  nickname: nickname.isEmpty ? username : nickname,
  avatarUrl: '',
);

void main() {
  test('findCommonFriends matches usernames case-insensitively', () {
    final common = findCommonFriends(
      [_user('Alice'), _user('bob'), _user('only-me')],
      [_user('BOB', nickname: '小明'), _user('alice'), _user('only-them')],
    );

    expect(common.map((user) => user.username), ['BOB', 'alice']);
    expect(common.first.nickname, '小明');
  });

  test('findCommonFriends removes duplicate rows from the second list', () {
    final common = findCommonFriends(
      [_user('alice')],
      [_user('ALICE'), _user('alice')],
    );

    expect(common, hasLength(1));
  });
}
