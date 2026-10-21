import 'dart:async';

import 'package:flutter/foundation.dart';

enum LoginCheckId {
  api('Bangumi 账号', '收藏、进度与评分接口'),
  website('网页登录', '好友聊天、小组与好友动态'),
  collections('收藏与进度', '读取你的收藏统计'),
  community('社区与电波提醒', '读取社区接口与提醒'),
  friendsTimeline('好友动态', '使用网页登录读取最新好友动态'),
  messages('私信', '使用网页登录读取收件箱');

  const LoginCheckId(this.title, this.purpose);
  final String title;
  final String purpose;

  /// Entering home requires both credential domains, not every feature.
  bool get required => this == LoginCheckId.api || this == LoginCheckId.website;

  bool get needsWebsite =>
      this == LoginCheckId.friendsTimeline || this == LoginCheckId.messages;
}

enum LoginCheckStatus { waiting, running, passed, failed, blocked }

class LoginCheckResult {
  const LoginCheckResult(this.status, [this.detail]);
  final LoginCheckStatus status;
  final String? detail;
}

/// A read-only probe; it throws, or returns a failure message, when the
/// feature cannot be used. Probes never post, send or change account data.
typedef LoginCheckProbe = Future<String?> Function();

/// Checks every account-backed feature once, right after a new login.
class FirstLoginChecks extends ChangeNotifier {
  FirstLoginChecks(
    Map<LoginCheckId, LoginCheckProbe> probes, {
    this.timeout = const Duration(seconds: 20),
  }) : _probes = Map.unmodifiable(probes) {
    assert(probes.length == LoginCheckId.values.length);
  }

  final Map<LoginCheckId, LoginCheckProbe> _probes;
  final Duration timeout;
  final _results = <LoginCheckId, LoginCheckResult>{
    for (final id in LoginCheckId.values)
      id: const LoginCheckResult(LoginCheckStatus.waiting),
  };
  final _generations = <LoginCheckId, int>{};
  bool _disposed = false;

  LoginCheckResult operator [](LoginCheckId id) => _results[id]!;

  bool get running => _results.values.any(
    (result) => result.status == LoginCheckStatus.running,
  );

  /// Feature checks never hold the user back; they only warm caches.
  bool get canEnter => LoginCheckId.values
      .where((id) => id.required)
      .every((id) => this[id].status == LoginCheckStatus.passed);

  int get failedCount => _results.values
      .where(
        (result) =>
            result.status == LoginCheckStatus.failed ||
            result.status == LoginCheckStatus.blocked,
      )
      .length;

  Future<void> runAll() async {
    await Future.wait([
      for (final id in LoginCheckId.values)
        if (!id.needsWebsite) run(id),
    ]);
  }

  /// Runs one check; a passing website check then runs its dependents.
  Future<void> run(LoginCheckId id) async {
    if (_disposed) return;
    if (id.needsWebsite &&
        this[LoginCheckId.website].status != LoginCheckStatus.passed) {
      _set(id, const LoginCheckResult(LoginCheckStatus.blocked, '需要先完成网页登录'));
      return;
    }
    final generation = (_generations[id] ?? 0) + 1;
    _generations[id] = generation;
    _set(id, const LoginCheckResult(LoginCheckStatus.running));
    LoginCheckResult result;
    try {
      final failure = await _probes[id]!().timeout(timeout);
      result = failure == null
          ? const LoginCheckResult(LoginCheckStatus.passed)
          : LoginCheckResult(LoginCheckStatus.failed, failure);
    } on TimeoutException {
      result = const LoginCheckResult(LoginCheckStatus.failed, '连接超时，请重试');
    } catch (error) {
      result = LoginCheckResult(
        LoginCheckStatus.failed,
        error.toString().replaceFirst('Exception: ', ''),
      );
    }
    if (_disposed || _generations[id] != generation) return;
    _set(id, result);
    if (id == LoginCheckId.website) {
      await Future.wait([
        for (final dependent in LoginCheckId.values)
          if (dependent.needsWebsite) run(dependent),
      ]);
    }
  }

  void _set(LoginCheckId id, LoginCheckResult result) {
    if (_disposed) return;
    _results[id] = result;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
