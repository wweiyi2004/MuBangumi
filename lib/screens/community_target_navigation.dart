import 'package:flutter/material.dart';
import '../models/bangumi_models.dart';
import '../models/community_models.dart';
import 'character_detail_screen.dart';
import 'person_detail_screen.dart';
import 'subject_detail_screen.dart';
import 'community_blog_screen.dart';

void openCommunityTimelineTarget(
  BuildContext context,
  CommunityTimelineTarget target,
) {
  final Widget page = switch (target.kind) {
    CommunityTimelineTargetKind.character => CharacterDetailScreen(
      characterId: target.id,
      seedName: target.title,
      seedImageUrl: target.imageUrl,
    ),
    CommunityTimelineTargetKind.person => PersonDetailScreen(
      personId: target.id,
      seedName: target.title,
      seedImageUrl: target.imageUrl,
    ),
    CommunityTimelineTargetKind.blog => CommunityBlogScreen(blogId: target.id),
    CommunityTimelineTargetKind.subject => SubjectDetailScreen(
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
