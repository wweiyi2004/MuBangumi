enum PmSendStatus {
  queued,
  preparing,
  sending,
  sent,
  waiting,
  failed,
  uncertain,
  cancelled,
}

class PmSendCommand {
  const PmSendCommand({
    required this.id,
    required this.ownerId,
    required this.compose,
    required this.receiver,
    required this.title,
    required this.body,
    required this.conversationId,
    required this.threadId,
    required this.related,
    required this.createdAt,
    this.status = PmSendStatus.queued,
    this.baseline = -1,
    this.error,
    this.sequence = 0,
    this.attempt = 0,
  });
  final String id, receiver, title, body, conversationId, threadId, related;
  final int ownerId, baseline, sequence, attempt;
  final bool compose;
  final DateTime createdAt;
  final PmSendStatus status;
  final String? error;
  String get targetKey => receiver.trim().toLowerCase();
  bool get finished =>
      status == PmSendStatus.sent || status == PmSendStatus.cancelled;
  String get label => switch (status) {
    PmSendStatus.queued => '待发送',
    PmSendStatus.preparing => '准备发送',
    PmSendStatus.sending => '发送中',
    PmSendStatus.sent => '已发送',
    PmSendStatus.waiting => '等待连接或登录',
    PmSendStatus.failed => '发送失败',
    PmSendStatus.uncertain => '结果待确认',
    PmSendStatus.cancelled => '已取消',
  };
  PmSendCommand copyWith({
    PmSendStatus? status,
    int? baseline,
    String? error,
    int? sequence,
    int? attempt,
  }) => PmSendCommand(
    id: id,
    ownerId: ownerId,
    compose: compose,
    receiver: receiver,
    title: title,
    body: body,
    conversationId: conversationId,
    threadId: threadId,
    related: related,
    createdAt: createdAt,
    status: status ?? this.status,
    baseline: baseline ?? this.baseline,
    error: error,
    sequence: sequence ?? this.sequence,
    attempt: attempt ?? this.attempt,
  );
  Map<String, dynamic> toJson() => {
    'compose': compose,
    'receiver': receiver,
    'title': title,
    'body': body,
    'conversation': conversationId,
    'thread': threadId,
    'related': related,
  };
  factory PmSendCommand.fromRow(
    Map<String, Object?> row,
    Map<String, dynamic> data,
  ) => PmSendCommand(
    id: row['command_id']! as String,
    ownerId: row['owner_id']! as int,
    compose: data['compose'] == true,
    receiver: data['receiver'] as String,
    title: data['title'] as String,
    body: data['body'] as String,
    conversationId: data['conversation'] as String,
    threadId: data['thread'] as String,
    related: data['related'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    status: PmSendStatus.values.byName(row['status']! as String),
    baseline: row['baseline']! as int,
    error: row['error'] as String?,
    sequence: row['sequence']! as int,
    attempt: row['attempt'] as int? ?? 0,
  );
}
