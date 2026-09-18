class AccountContentPreferencesException implements Exception {
  const AccountContentPreferencesException(this.statusCode);
  final int? statusCode;

  String get message => switch (statusCode) {
    401 => '登录凭证已失效，请重新登录后再保存',
    403 => 'Bangumi 拒绝修改此设置，请重新读取账号权限',
    429 => '操作过于频繁，请稍后重新读取设置',
    final int status when status >= 500 =>
      'Bangumi 设置接口暂时故障（HTTP $status），可前往官网设置受限内容',
    null => '连接中断，保存结果尚未确认，请重新读取设置',
    final status => '设置请求失败（HTTP $status），请重新读取或前往官网设置',
  };

  @override
  String toString() => message;
}

class AccountContentPreferences {
  const AccountContentPreferences({
    required this.showNsfwSubject,
    required this.canSetNsfwSubject,
    required this.allowNsfw,
  });

  final bool showNsfwSubject;
  final bool canSetNsfwSubject;
  final bool allowNsfw;

  factory AccountContentPreferences.fromJson(Map<String, dynamic> json) {
    final value = json['preferences'];
    if (value is! Map ||
        value['showNsfwSubject'] is! bool ||
        value['canSetNsfwSubject'] is! bool ||
        value['allowNsfw'] is! bool) {
      throw const FormatException('Bangumi 未返回完整的内容偏好，请重新读取');
    }
    return AccountContentPreferences(
      showNsfwSubject: value['showNsfwSubject'] as bool,
      canSetNsfwSubject: value['canSetNsfwSubject'] as bool,
      allowNsfw: value['allowNsfw'] as bool,
    );
  }
}
