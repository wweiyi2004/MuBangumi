import 'package:flutter/material.dart';
import '../models/bangumi_models.dart';
import 'subject_widgets.dart';
import '../core/theme/app_tokens.dart';

/// Progress is the user's recorded history, not a claim of resource availability.
class ContinueWatchingTile extends StatelessWidget {
  const ContinueWatchingTile({
    super.key,
    required this.collection,
    required this.onOpen,
    this.onNext,
    this.onEpisodes,
    this.onPin,
    this.pinned = false,
    this.busy = false,
  });
  final UserCollection collection;
  final VoidCallback onOpen;
  final VoidCallback? onNext, onEpisodes, onPin;
  final bool pinned, busy;

  @override
  Widget build(BuildContext context) {
    final subject = collection.subject;
    final episodes = subject.type.hasEpisodes;
    final books = subject.type.hasVolumes;
    final done = books ? collection.volumeStatus : collection.episodeStatus;
    final total = books ? subject.volumeCount : subject.episodeCount;
    final unit = books ? '卷' : '集';
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: AppRadius.medium,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SubjectCover(
                subject: subject,
                width: 60,
                height: 84,
                borderRadius: 6,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      episodes || books
                          ? total > 0
                                ? '已记录 $done / $total $unit'
                                : '已记录 $done $unit · 总数未知'
                          : collection.type.labelFor(subject.type),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if ((episodes || books) && total > 0) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (done / total).clamp(0, 1),
                        minHeight: 3,
                      ),
                    ],
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (onNext != null)
                          TextButton.icon(
                            onPressed: busy ? null : onNext,
                            icon: busy
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add_task_rounded, size: 18),
                            label: const Text('看完下一集'),
                          ),
                        if (onEpisodes != null)
                          IconButton(
                            onPressed: busy ? null : onEpisodes,
                            tooltip: '选择集数',
                            icon: const Icon(Icons.grid_view_rounded, size: 19),
                          ),
                        if (onPin != null)
                          IconButton(
                            onPressed: onPin,
                            tooltip: pinned ? '取消置顶' : '置顶到首页',
                            icon: Icon(
                              pinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              size: 18,
                              color: pinned ? scheme.primary : null,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
