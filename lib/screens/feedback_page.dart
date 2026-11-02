import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feedback/feedback_service.dart';
import '../core/feedback/feedback_submission.dart';
import '../state/service_providers.dart';

class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({super.key});

  @override
  ConsumerState<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends ConsumerState<FeedbackPage> {
  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  final _email = TextEditingController();
  FeedbackCategory _category = FeedbackCategory.problem;
  bool _includeDeviceInfo = true;
  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  String _categoryLabel(FeedbackCategory category) => switch (category) {
    FeedbackCategory.problem => '反馈问题',
    FeedbackCategory.suggestion => '提出建议',
    FeedbackCategory.other => '其他',
  };

  String get _contentHint => switch (_category) {
    FeedbackCategory.problem => '在哪个页面、做了什么操作？实际出现了什么情况？',
    FeedbackCategory.suggestion => '在什么场景下需要？你希望怎样改进？',
    FeedbackCategory.other => '想说些什么？',
  };

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(feedbackServiceProvider)
          .submit(
            category: _category,
            message: _message.text,
            email: _email.text,
            includeDeviceInfo: _includeDeviceInfo,
          );
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is FeedbackException ? error.message : '提交失败，请检查网络后稍后重试';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('意见反馈')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              ((constraints.maxWidth - 640) / 2).clamp(16, double.infinity),
              16,
              ((constraints.maxWidth - 640) / 2).clamp(16, double.infinity),
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _sent ? _buildSuccess(context) : _buildForm(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 56,
            color: colors.primary,
          ),
          const SizedBox(height: 20),
          Text('反馈已发送', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('感谢反馈，作者会认真阅读。'),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '说清楚具体页面、操作或期待的效果即可。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in FeedbackCategory.values)
                ChoiceChip(
                  label: Text(_categoryLabel(category)),
                  selected: _category == category,
                  onSelected: _submitting
                      ? null
                      : (_) => setState(() {
                          _category = category;
                          _error = null;
                        }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _message,
            enabled: !_submitting,
            minLines: 7,
            maxLines: 12,
            maxLength: 4000,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: '反馈内容',
              hintText: _contentHint,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _error = null),
            validator: (value) {
              final length = value?.trim().length ?? 0;
              return length == 0 ? '请填写反馈内容' : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: '联系邮箱（选填）',
              hintText: '需要作者回复时填写',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return null;
              return email.length <= 254 &&
                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                  ? null
                  : '请输入有效的邮箱地址';
            },
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('附带版本与平台信息'),
            subtitle: const Text('仅用于定位问题，不包含账号或聊天内容'),
            value: _includeDeviceInfo,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _includeDeviceInfo = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting || _message.text.trim().isEmpty
                ? null
                : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('提交反馈'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '反馈将以邮件发送给作者，不会公开发布。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
