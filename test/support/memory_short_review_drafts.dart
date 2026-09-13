import 'package:mubangumi/core/storage/community_draft_store.dart';

class MemoryShortReviewDrafts extends CommunityDraftRepository {
  final data = <String, CommunityDraftSlot>{};
  bool fail = false;
  @override
  Future<CommunityDraftData?> load(String key) async => data[key]?.data;
  @override
  Future<CommunityDraftSlot> loadVersioned(String key) async =>
      data[key] ?? const CommunityDraftSlot();
  @override
  Future<void> save(String key, CommunityDraftData draft) async {
    await saveVersioned(key, draft, expectedRevision: data[key]?.revision ?? 0);
  }

  @override
  Future<int> saveVersioned(
    String key,
    CommunityDraftData draft, {
    required int expectedRevision,
  }) async {
    if (fail) throw StateError('disk full');
    if ((data[key]?.revision ?? 0) != expectedRevision) {
      throw const CommunityDraftConflict();
    }
    data[key] = CommunityDraftSlot(
      revision: expectedRevision + 1,
      data: draft.title.isEmpty && draft.content.isEmpty ? null : draft,
    );
    return expectedRevision + 1;
  }
}
