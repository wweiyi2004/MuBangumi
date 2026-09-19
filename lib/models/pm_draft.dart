import 'dart:convert';
import 'dart:math';

enum PmDraftKind { compose, reply }

class PmDraft {
  const PmDraft({
    required this.id,
    required this.ownerId,
    required this.kind,
    this.recipient = '',
    this.title = '',
    this.body = '',
    this.conversationId = '',
    this.threadId = '',
  });
  final String id;
  final int ownerId;
  final PmDraftKind kind;
  final String recipient;
  final String title;
  final String body;
  final String conversationId;
  final String threadId;
  bool get isEmpty => kind == PmDraftKind.reply
      ? body.isEmpty
      : recipient.trim().isEmpty && title.isEmpty && body.isEmpty;
  PmDraft edited({
    required String recipient,
    required String title,
    required String body,
  }) => PmDraft(
    id: id,
    ownerId: ownerId,
    kind: kind,
    recipient: recipient,
    title: title,
    body: body,
    conversationId: conversationId,
    threadId: threadId,
  );
  Map<String, dynamic> toJson() => {
    'recipient': recipient,
    'title': title,
    'body': body,
    'conversation_id': conversationId,
    'thread_id': threadId,
  };
  static String newId() => base64UrlEncode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  );
  static String replyId(String conversation, String thread) =>
      jsonEncode(['reply', conversation, thread]);
}

class PmDraftSlot {
  const PmDraftSlot({this.draft, this.revision = 0});
  final PmDraft? draft;
  final int revision;
}

class PmDraftConflict implements Exception {
  const PmDraftConflict();
  @override
  String toString() => '草稿已在另一处更新，请保留当前输入并重新打开草稿';
}

abstract class PmDraftRepository {
  Future<PmDraftSlot> read(int ownerId, String id);
  Future<PmDraftSlot?> findCompose(int ownerId, {String? recipient});
  Future<List<PmDraft>> listCompose(int ownerId);
  Future<int> save(PmDraft draft, {required int expectedRevision});
  Future<int> clear(int ownerId, String id, {required int expectedRevision});
}
