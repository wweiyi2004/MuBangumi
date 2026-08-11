// Bangumi website private-message models (parsed from bgm.tv HTML).

class PmConversation {
  const PmConversation({
    required this.id,
    required this.title,
    required this.preview,
    required this.peerName,
    required this.peerUserId,
    this.avatarUrl = '',
    this.timeText = '',
    this.isUnread = false,
  });

  final String id;
  final String title;
  final String preview;
  final String peerName;
  final String peerUserId;
  final String avatarUrl;
  final String timeText;
  final bool isUnread;
}

class PmMessage {
  const PmMessage({
    required this.name,
    required this.userId,
    required this.contentHtml,
    required this.timeText,
    this.avatarUrl = '',
    this.isSelf = false,
    this.threadId,
  });

  final String name;
  final String userId;
  final String contentHtml;
  final String timeText;
  final String avatarUrl;
  final bool isSelf;
  final String? threadId;

  /// Plain text approximation for list/chat bubbles.
  String get contentText {
    final withoutTags = contentHtml
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .trim();
    return withoutTags;
  }
}

class PmThreadFilter {
  const PmThreadFilter({
    required this.id,
    required this.title,
    this.current = false,
  });

  final String id;
  final String title;
  final bool current;
}

class PmReplyForm {
  const PmReplyForm({
    required this.formhash,
    required this.msgReceivers,
    this.related = '',
    this.msgTitle = '',
    this.newTopic,
  });

  final String formhash;
  final String msgReceivers;
  final String related;
  final String msgTitle;
  final String? newTopic;

  bool get isValid => formhash.isNotEmpty && msgReceivers.isNotEmpty;
}

class PmConversationDetail {
  const PmConversationDetail({
    required this.messages,
    required this.form,
    this.peerName = '',
    this.peerUserId = '',
    this.threads = const [],
  });

  final List<PmMessage> messages;
  final PmReplyForm form;
  final String peerName;
  final String peerUserId;
  final List<PmThreadFilter> threads;
}

class PmComposeParams {
  const PmComposeParams({
    required this.formhash,
    required this.msgReceivers,
  });

  final String formhash;
  final String msgReceivers;

  bool get isValid => formhash.isNotEmpty && msgReceivers.isNotEmpty;
}

class PmAuthException implements Exception {
  const PmAuthException([
    this.message = '需要先同步 Bangumi 网站登录才能使用站内短信',
  ]);

  final String message;

  @override
  String toString() => message;
}

class PmException implements Exception {
  const PmException(this.message);

  final String message;

  @override
  String toString() => message;
}
