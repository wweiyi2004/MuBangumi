import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';

/// Existing widget fixtures model API cursor paging, without live HTTP reads.
mixin ApiTimelineFixture on CommunityService {
  @override
  Future<CommunityTimelinePageResult?> readCachedTimelinePage(
    CommunityTimelineMode mode,
  ) async {
    final rows = await readCachedTimeline(mode);
    return rows == null ? null : CommunityTimelinePageResult.api(rows);
  }

  @override
  Future<CommunityTimelinePageResult> loadFreshTimelinePage(
    CommunityTimelineMode mode, {
    String? username,
    int? until,
    int? websitePage,
    bool refresh = false,
  }) async => CommunityTimelinePageResult.api(
    username?.isNotEmpty == true
        ? await loadUserTimeline(username!, until: until, refresh: refresh)
        : await loadTimeline(mode, until: until, refresh: refresh),
  );
}
