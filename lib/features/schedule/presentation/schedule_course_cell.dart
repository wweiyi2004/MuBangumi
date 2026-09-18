import 'package:flutter/material.dart';
import '../../../models/bangumi_models.dart';
import '../../../models/schedule_models.dart';
import '../../../widgets/subject_widgets.dart';
import '../../../widgets/readable_subject_title.dart';

class ScheduleDragPayload {
  const ScheduleDragPayload(this.item, this.season);
  final ScheduleItem item;
  final SeasonKey season;
}

enum ScheduleCellStyle { chip, grid, dense }

class ScheduleCourseCell extends StatelessWidget {
  const ScheduleCourseCell({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onActions,
    required this.season,
    this.collection,
    this.style = ScheduleCellStyle.grid,
    this.dense = false,
    this.enableDrag = false,
    this.unreadCount = 0,
    this.onDragStarted,
    this.onDragEnded,
  });

  final ScheduleItem item;
  final UserCollection? collection;
  final VoidCallback onOpen;
  final VoidCallback onActions;
  final SeasonKey season;
  final ScheduleCellStyle style;
  final bool dense;
  final bool enableDrag;
  final int unreadCount;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subject = Subject(
      id: item.subjectId,
      name: item.name,
      nameCn: item.nameCn,
      imageUrl: item.imageUrl,
      summary: '',
      episodeCount: item.episodeCount,
      score: 0,
      rank: 0,
      date: '',
      type: item.type,
    );
    final progress = collection == null
        ? null
        : collection!.subject.episodeCount > 0
        ? '${collection!.episodeStatus}/${collection!.subject.episodeCount}'
        : null;

    final showMenuButton = style == ScheduleCellStyle.grid && !dense;
    final content = switch (style) {
      ScheduleCellStyle.chip => SizedBox(
        width: 84,
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SubjectCover(
                      subject: subject,
                      width: 48,
                      height: constraints.maxHeight,
                      borderRadius: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                ReadableSubjectTitle(
                  item.displayName,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Positioned(
              top: -4,
              right: -8,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: '更多',
                icon: const Icon(Icons.more_vert_rounded, size: 16),
                onPressed: onActions,
              ),
            ),
          ],
        ),
      ),
      ScheduleCellStyle.dense => Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SubjectCover(
                    subject: subject,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    borderRadius: 6,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 22,
                child: ReadableSubjectTitle(
                  item.displayName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: -6,
            right: -8,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              tooltip: '删除/改期',
              icon: Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: scheme.onSurface.withValues(alpha: .75),
              ),
              onPressed: onActions,
            ),
          ),
        ],
      ),
      ScheduleCellStyle.grid =>
        dense
            ? Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => SubjectCover(
                            subject: subject,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            borderRadius: 6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      ReadableSubjectTitle(
                        item.displayName,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: -6,
                    right: -8,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      tooltip: '删除/改期',
                      icon: const Icon(Icons.more_horiz_rounded, size: 16),
                      onPressed: onActions,
                    ),
                  ),
                ],
              )
            : LayoutBuilder(
                builder: (context, cellConstraints) {
                  final tight = cellConstraints.maxWidth < 120;
                  final coverW = tight ? 32.0 : 40.0;
                  final coverH = tight ? 46.0 : 56.0;
                  return Row(
                    children: [
                      SubjectCover(
                        subject: subject,
                        width: coverW,
                        height: coverH,
                        borderRadius: 7,
                      ),
                      SizedBox(width: tight ? 4 : 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ReadableSubjectTitle(
                              item.displayName,
                              maxLines: tight ? 1 : 2,
                              style: TextStyle(
                                fontSize: tight ? 11 : 12,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            if (progress != null && !tight) ...[
                              const SizedBox(height: 2),
                              Text(
                                progress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSecondaryContainer,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (showMenuButton && !tight)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: '更多',
                          icon: const Icon(Icons.more_vert_rounded, size: 18),
                          onPressed: onActions,
                        ),
                    ],
                  );
                },
              ),
    };

    final radius = dense || style == ScheduleCellStyle.dense ? 8.0 : 10.0;
    final card = Material(
      color: scheme.secondaryContainer.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onOpen,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(
                dense || style == ScheduleCellStyle.dense ? 3 : 5,
              ),
              child: content,
            ),
            if (unreadCount > 0)
              Positioned(
                left: 2,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: TextStyle(
                      color: scheme.onError,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            if (item.reminderEnabled && item.isScheduled)
              Positioned(
                right: 3,
                bottom: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: .92),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.notifications_active_rounded,
                      size: 12,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!enableDrag) return card;

    return LongPressDraggable<ScheduleDragPayload>(
      data: ScheduleDragPayload(item, season),
      hapticFeedbackOnStart: true,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded?.call(),
      onDraggableCanceled: (_, _) => onDragEnded?.call(),
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 72,
          height: 96,
          child: Column(
            children: [
              Expanded(
                child: SubjectCover(
                  subject: subject,
                  width: 72,
                  height: 72,
                  borderRadius: 0,
                ),
              ),
              ColoredBox(
                color: scheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: ReadableSubjectTitle(
                    item.displayName,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.28, child: card),
      child: card,
    );
  }
}
