import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/pm_service.dart';
import '../../../models/pm_models.dart';
import '../../../models/pm_send_command.dart';
import '../../../state/pm_send_queue_controller.dart';
import 'pm_chat_widgets.dart';
import '../../../core/theme/app_tokens.dart';

class PmQueuedBubble extends StatelessWidget {
  const PmQueuedBubble({
    super.key,
    required this.command,
    required this.queue,
    this.avatar = '',
  });
  final PmSendCommand command;
  final PmSendQueueController queue;
  final String avatar;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      PmChatBubble(
        message: PmMessage(
          name: '我',
          userId: '${command.ownerId}',
          isSelf: true,
          contentHtml: const HtmlEscape(
            HtmlEscapeMode.element,
          ).convert(command.body).replaceAll('\n', '<br>'),
          timeText: '',
        ),
        avatar: avatar,
      ),
      Padding(
        padding: const EdgeInsets.only(right: 50, bottom: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (command.status == PmSendStatus.sending ||
                command.status == PmSendStatus.preparing)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: SizedBox.square(
                  dimension: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ),
            Text(
              command.label,
              style: TextStyle(
                fontSize: AppText.caption,
                color:
                    command.status == PmSendStatus.failed ||
                        command.status == PmSendStatus.uncertain
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (!command.finished)
              IconButton(
                tooltip: '发送任务详情',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_horiz, size: 18),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: PmSendTaskActions(command: command, queue: queue),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class PmSendQueueScreen extends ConsumerWidget {
  const PmSendQueueScreen({super.key, required this.service});
  final PmService service;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(pmSendQueueProvider(service));
    final entries = queue.entries
        .where((e) => e.status != PmSendStatus.cancelled)
        .toList()
        .reversed
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('发送队列'),
        actions: [
          IconButton(
            tooltip: '重新读取队列',
            onPressed: () async {
              await queue.reload();
              queue.wake();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(child: Text(queue.error ?? '没有待发送的私信'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final command = entries[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${command.compose ? '新私信' : '私聊回复'} · ${command.receiver}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (command.title.isNotEmpty) Text(command.title),
                        const SizedBox(height: 10),
                        SelectableText(command.body),
                        const SizedBox(height: 10),
                        PmSendTaskActions(command: command, queue: queue),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class PmSendTaskActions extends StatefulWidget {
  const PmSendTaskActions({
    super.key,
    required this.command,
    required this.queue,
  });
  final PmSendCommand command;
  final PmSendQueueController queue;
  @override
  State<PmSendTaskActions> createState() => _PmSendTaskActionsState();
}

class _PmSendTaskActionsState extends State<PmSendTaskActions> {
  bool _busy = false;
  String? _message;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _message = '操作未完成，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.queue,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final command =
        widget.queue.entries
            .where((e) => e.id == widget.command.id)
            .firstOrNull ??
        widget.command;
    final uncertain = command.status == PmSendStatus.uncertain;
    final retryable =
        command.status == PmSendStatus.failed ||
        command.status == PmSendStatus.waiting;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          command.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (command.error != null) Text(command.error!),
        if (_message != null) Text(_message!),
        Wrap(
          spacing: 8,
          children: [
            if (retryable)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.queue.retry(command)),
                child: const Text('重试发送'),
              ),
            if (uncertain && !command.compose)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final confirmed = await widget.queue.check(command);
                        if (mounted) {
                          setState(
                            () => _message = confirmed
                                ? '已在会话中核对到发送内容'
                                : '暂未确认，请打开会话核对后再决定是否重发',
                          );
                        }
                      }),
                child: const Text('核对发送结果'),
              ),
            if (uncertain)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('确认重新发送？'),
                            content: const Text('上一条可能已送达。请先核对会话；重发可能产生重复消息。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('返回核对'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('我已核对，仍要重发'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await _run(
                            () => widget.queue.retry(
                              command,
                              confirmedUncertain: true,
                            ),
                          );
                        }
                      },
                child: const Text('核对后重新发送'),
              ),
            if (retryable || uncertain || command.status == PmSendStatus.queued)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.queue.cancel(command)),
                child: Text(uncertain ? '停止此任务' : '取消发送'),
              ),
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: command.body)),
              child: const Text('复制内容'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
