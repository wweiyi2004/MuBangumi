import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/pm_service.dart';
import '../../../state/service_providers.dart';
import '../../../state/pm_send_queue_controller.dart';
import 'pm_send_queue_view.dart';

class PmQueueAction extends ConsumerWidget {
  const PmQueueAction({super.key, this.service});
  final PmService? service;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = service ?? pmServiceFor(context);
    final queue = ref.watch(pmSendQueueProvider(client));
    if (!queue.supported) return const SizedBox.shrink();
    final attention = queue.attentionCount;
    return IconButton(
      tooltip: attention > 0 ? '发送队列 · $attention 项需要处理' : '发送队列',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PmSendQueueScreen(service: client),
        ),
      ),
      icon: Badge(
        isLabelVisible: queue.activeCount > 0 || attention > 0,
        backgroundColor: attention > 0
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        label: queue.activeCount > 0
            ? Text('${queue.activeCount}')
            : const Text('!'),
        child: const Icon(Icons.outbox_outlined),
      ),
    );
  }
}
