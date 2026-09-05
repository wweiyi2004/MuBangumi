import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../widgets/login_progress.dart';

class LoginPreparationScreen extends StatefulWidget {
  const LoginPreparationScreen({super.key, this.nickname, this.onEnter});

  final String? nickname;
  final VoidCallback? onEnter;

  @override
  State<LoginPreparationScreen> createState() => _LoginPreparationScreenState();
}

class _LoginPreparationScreenState extends State<LoginPreparationScreen> {
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preparing = widget.onEnter != null;
    final name = widget.nickname?.trim() ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: LoginEntrance(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandMark(size: 72),
                    const SizedBox(height: 28),
                    Text(
                      preparing
                          ? name.isEmpty
                                ? '登录成功'
                                : '欢迎，$name'
                          : '正在连接 Bangumi',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      preparing ? '正在准备你的首页' : '正在恢复登录',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    if (preparing)
                      LoginProgress(
                        stage: 2,
                        detail: _slow ? '连接比平时慢一些，你可以先进入，收藏会继续加载。' : '',
                      )
                    else ...[
                      const LinearProgressIndicator(minHeight: 4),
                      if (_slow) ...[
                        const SizedBox(height: 14),
                        Text(
                          '连接较慢，请稍候…',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                    if (preparing) ...[
                      const SizedBox(height: 20),
                      TextButton(
                        key: const Key('enter-home-now-button'),
                        onPressed: widget.onEnter,
                        child: const Text('先进入，后台加载'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
