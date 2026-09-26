import 'dart:convert';

/// The request may have committed. Only read-back or an explicit user decision
/// can unlock another submission; this is not a normal retryable failure.
class CommunitySubmissionUncertain extends FormatException {
  const CommunitySubmissionUncertain([
    super.message = '发帖结果未知，内容已保留，请先核对发布结果，避免重复发帖',
  ]);
}

class CommunitySubmissionRejected extends FormatException {
  const CommunitySubmissionRejected(super.message);
}

/// Stored with the existing account/group draft, including across app restarts.
/// Older plain-text drafts remain readable; no credentials are stored here.
class CommunityTopicDraft {
  DateTime? attemptedAt;
  int? confirmedId;
  bool get pending => attemptedAt != null;

  void clearAttempt() {
    attemptedAt = null;
    confirmedId = null;
  }

  String encode(String body) => jsonEncode({
    'mubangumi_draft': 'group-topic',
    'version': 1,
    'body': body,
    'attempted_at': attemptedAt?.toUtc().toIso8601String(),
    'confirmed_id': confirmedId,
  });

  String restore(String encoded) {
    Object? value;
    try {
      value = jsonDecode(encoded);
    } on FormatException {
      clearAttempt();
      return encoded;
    }
    if (value is! Map || value['mubangumi_draft'] != 'group-topic') {
      clearAttempt();
      return encoded;
    }
    if (value['version'] != 1 ||
        value['body'] is! String ||
        (value['attempted_at'] != null &&
            DateTime.tryParse(value['attempted_at'].toString()) == null)) {
      throw const FormatException('发帖草稿记录不完整');
    }
    attemptedAt = DateTime.tryParse(value['attempted_at']?.toString() ?? '');
    confirmedId = value['confirmed_id'] is int && value['confirmed_id'] > 0
        ? value['confirmed_id'] as int
        : null;
    return value['body'] as String;
  }
}
