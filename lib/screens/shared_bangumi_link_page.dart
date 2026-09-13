import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/shortcuts/shared_bangumi_link.dart';
import '../models/bangumi_models.dart';
import '../models/community_models.dart';
import '../state/session_controller.dart';
import 'subject_detail_screen.dart';
import 'person_detail_screen.dart';
import 'character_detail_screen.dart';
import 'community_topic_screen.dart';

final sharedSubjectProvider = FutureProvider.autoDispose.family<Subject, int>(
  (ref, id) => ref.watch(bangumiApiProvider).getSubject(id),
);

class SharedBangumiLinkPage extends ConsumerWidget {
  const SharedBangumiLinkPage({super.key, required this.link});
  final SharedBangumiLink link;
  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (link.kind) {
    SharedBangumiKind.person => PersonDetailScreen(personId: link.id),
    SharedBangumiKind.character => CharacterDetailScreen(characterId: link.id),
    SharedBangumiKind.subject =>
      ref
          .watch(sharedSubjectProvider(link.id))
          .when(
            data: (subject) => SubjectDetailScreen(subject: subject),
            loading: () => Scaffold(
              appBar: AppBar(title: const Text('打开分享条目')),
              body: const Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Scaffold(
              appBar: AppBar(title: const Text('打开分享条目')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('条目暂时无法打开，请检查网络或确认条目仍然存在。'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(sharedSubjectProvider(link.id)),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    _ => CommunityTopicScreen(
      topic: CommunityTopic(
        id: link.id,
        kind: switch (link.kind) {
          SharedBangumiKind.groupTopic => CommunityTopicKind.group,
          SharedBangumiKind.subjectTopic => CommunityTopicKind.subject,
          _ => CommunityTopicKind.episode,
        },
        title: link.label,
        url: link.url,
        webUrl: link.url,
      ),
    ),
  };
}
