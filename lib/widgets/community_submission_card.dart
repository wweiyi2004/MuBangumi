import 'package:flutter/material.dart';
import '../state/community_submission_controller.dart';
import 'community_rich_content.dart';

class CommunitySubmissionCard extends StatelessWidget {
  const CommunitySubmissionCard({
    super.key,
    required this.entry,
    required this.onInspect,
  });
  final CommunityPendingSubmission entry;
  final VoidCallback onInspect;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(switch (entry.status) {
                CommunitySubmissionStatus.publishing => Icons.schedule_rounded,
                CommunitySubmissionStatus.sent =>
                  Icons.check_circle_outline_rounded,
                _ => Icons.info_outline_rounded,
              }, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(switch (entry.status) {
                  CommunitySubmissionStatus.publishing => '发布中',
                  CommunitySubmissionStatus.sent => '已发布',
                  CommunitySubmissionStatus.failed => '发布失败，内容已保留',
                  CommunitySubmissionStatus.uncertain => '结果待确认，请勿重复发布',
                }),
              ),
            ],
          ),
          if (entry.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                entry.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          const SizedBox(height: 8),
          CommunityRichContent(entry.content),
          if (entry.error != null) Text(entry.error!),
          if (entry.status != CommunitySubmissionStatus.publishing)
            TextButton(
              onPressed: onInspect,
              child: Text(
                entry.status == CommunitySubmissionStatus.failed
                    ? '重新编辑并验证'
                    : '核对发布结果',
              ),
            ),
        ],
      ),
    ),
  );
}
