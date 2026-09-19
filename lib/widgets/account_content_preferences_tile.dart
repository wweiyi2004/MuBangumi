import '../state/service_providers.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/network/community_service.dart';
import '../models/account_content_preferences.dart';

class AccountContentPreferencesTile extends StatefulWidget {
  const AccountContentPreferencesTile({
    super.key,
    this.service,
    this.onOpenWebsite,
  });
  final CommunityService? service;
  final Future<void> Function()? onOpenWebsite;

  @override
  State<AccountContentPreferencesTile> createState() =>
      _AccountContentPreferencesTileState();
}

class _AccountContentPreferencesTileState
    extends State<AccountContentPreferencesTile> {
  late final _service = widget.service ?? communityServiceFor(context);
  AccountContentPreferences? _preferences;
  bool _busy = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _service.accountChanges.addListener(_accountChanged);
    unawaited(_load());
  }

  void _accountChanged() {
    _generation++;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() => _preferences = null);
      unawaited(_load());
    });
  }

  Future<void> _load({bool refreshContent = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.loadContentPreferences();
      if (!mounted || generation != _generation) return;
      if (refreshContent ||
          (_preferences != null &&
              result.showNsfwSubject != _preferences!.showNsfwSubject)) {
        await _service.refreshContentAfterPreferenceChange();
      }
      if (mounted && generation == _generation) {
        setState(() => _preferences = result);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '无法读取账号内容偏好，请检查连接后重试');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save(bool enabled) async {
    if (_busy || _error != null || _preferences?.canSetNsfwSubject != true) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.setNsfwPreference(enabled);
      if (!mounted || generation != _generation) return;
      setState(() => _preferences = result);
      if (result.showNsfwSubject != enabled) {
        setState(() => _error = 'Bangumi 尚未确认这次变更，请重新读取或前往官网设置');
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到 Bangumi；若动态尚未更新，请约一分钟后下拉刷新')),
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is AccountContentPreferencesException
              ? error.message
              : '未能确认保存结果，请重新读取设置，或前往官网修改',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _openWebsite() async {
    if (_busy || widget.onOpenWebsite == null) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onOpenWebsite!();
      if (mounted && generation == _generation) {
        await _load(refreshContent: true);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _error = '未能打开官网设置，请检查网页登录后重试';
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _service.accountChanges.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    final description = preferences == null
        ? (_busy ? '正在读取 Bangumi 账号设置…' : '尚未读取到账号设置')
        : !preferences.canSetNsfwSubject
        ? 'Bangumi 暂不允许此账号修改，通常需注册满 60 天'
        : preferences.showNsfwSubject && !preferences.allowNsfw
        ? '偏好已开启，但当前账号的内容访问权限仍受限制'
        : '同步 Bangumi 账号，控制受限条目在社区等页面的显示';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preferences == null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('显示 NSFW 条目'),
            subtitle: Text(description),
            trailing: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          )
        else
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('显示 NSFW 条目'),
            subtitle: Text(description),
            value: preferences.showNsfwSubject,
            onChanged: _busy || _error != null || !preferences.canSetNsfwSubject
                ? null
                : _save,
          ),
        if (_busy && preferences != null) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (widget.onOpenWebsite != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _openWebsite,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('在官网设置受限内容'),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(_error == null ? '重新读取内容偏好' : '重新读取设置'),
          ),
        ),
      ],
    );
  }
}
