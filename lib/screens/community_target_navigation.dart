import '../navigation/app_destination.dart';
import 'package:flutter/material.dart';
import '../models/bangumi_models.dart';
import '../models/community_models.dart';

void openCommunityTimelineTarget(
  BuildContext context,
  CommunityTimelineTarget target,
) {
  final Widget page = switch (target.kind) {
    CommunityTimelineTargetKind.character => CharacterRoute(
      characterId: target.id,
      seedName: target.title,
      seedImageUrl: target.imageUrl,
    ),
    CommunityTimelineTargetKind.person => PersonRoute(
      personId: target.id,
      seedName: target.title,
      seedImageUrl: target.imageUrl,
    ),
    CommunityTimelineTargetKind.blog => BlogRoute(blogId: target.id),
    CommunityTimelineTargetKind.subject => SubjectRoute(
      subject: Subject(
        id: target.id,
        name: target.title,
        nameCn: '',
        imageUrl: target.imageUrl,
        summary: '',
        episodeCount: 0,
        score: 0,
        rank: 0,
        date: '',
        type: SubjectType.fromValue(target.subjectType),
      ),
    ),
  };
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}
