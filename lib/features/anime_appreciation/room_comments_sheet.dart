import 'dart:async';
import 'package:flutter/material.dart';
import 'package:banjian_server/banjian_server.dart';
import 'room_connection.dart';

String roomCommentsStateKey(Json? event, String round) {
  final rounds = (event?['rounds'] as List?) ?? const [];
  final r = rounds.where((v) => v['id'] == round).firstOrNull;
  // Historical pages stay stable while new comments arrive. Moderation and
  // visibility changes still invalidate them; the main preview remains live.
  return '${event?['id']}:${event?['version']}:${r?['commentsOpen'] ?? r?['publicComments']}';
}

Future<void> showRoomComments(
  BuildContext context, {
  required RoomApi api,
  required String eventId,
  required String roundId,
  required Listenable live,
  required String Function() stateKey,
  required bool Function() isCurrent,
  Future<void> Function(RoomComment)? onModerate,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: .85,
    child: RoomCommentsBrowser(
      api: api,
      eventId: eventId,
      roundId: roundId,
      live: live,
      stateKey: stateKey,
      isCurrent: isCurrent,
      onModerate: onModerate,
    ),
  ),
);

class RoomCommentsBrowser extends StatefulWidget {
  const RoomCommentsBrowser({
    super.key,
    required this.api,
    required this.eventId,
    required this.roundId,
    required this.live,
    required this.stateKey,
    required this.isCurrent,
    this.onModerate,
  });
  final RoomApi api;
  final String eventId, roundId;
  final Listenable live;
  final String Function() stateKey;
  final bool Function() isCurrent;
  final Future<void> Function(RoomComment)? onModerate;
  @override
  State<RoomCommentsBrowser> createState() => _RoomCommentsBrowserState();
}

class _RoomCommentsBrowserState extends State<RoomCommentsBrowser> {
  RoomCommentsPage? _page;
  String? _error;
  bool _busy = false;
  int _request = 0;
  final _cursors = <int?>[null];
  late String _stateKey;
  Timer? _refresh;
  @override
  void initState() {
    super.initState();
    _stateKey = widget.stateKey();
    widget.live.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    final next = widget.stateKey();
    if (next == _stateKey) return;
    _stateKey = next;
    // Revoke the old projection immediately, including requests in flight.
    // A changed visibility rule can also make a historical cursor meaningless.
    _request++;
    _cursors
      ..clear()
      ..add(null);
    setState(() {
      _page = null;
      _error = null;
      _busy = true;
    });
    _refresh?.cancel();
    _refresh = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(_load()),
    );
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!widget.isCurrent()) {
      setState(() {
        _page = null;
        _error = '活动已变化，请重新打开评论';
        _busy = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = Uri(
        path: 'comments',
        queryParameters: {
          'event': widget.eventId,
          'round': widget.roundId,
          'limit': '${RoomLimits.commentPageSize}',
          if (_cursors.last != null) 'before': '${_cursors.last}',
        },
      );
      final page = RoomCommentsPage.fromJson(
        await widget.api.request(path.toString()),
      );
      if (page.eventId != widget.eventId || page.roundId != widget.roundId) {
        throw const FormatException('评论所属活动不符');
      }
      if (mounted && request == _request && widget.isCurrent()) {
        setState(() => _page = page);
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _page = null;
          _error = '评论加载失败，请重试';
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _moderate(RoomComment comment) async {
    if (!widget.isCurrent() || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onModerate!(comment);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _request++;
    _refresh?.cancel();
    widget.live.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '匿名短评${_page == null ? '' : ' · ${_page!.total} 条'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '刷新评论',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(
          child: ListView.builder(
            itemCount: _page?.comments.length ?? 0,
            itemBuilder: (context, i) {
              final c = _page!.comments[i];
              return ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(c.mine ? '我 · 匿名短评' : '匿名短评'),
                subtitle: Text('${c.text}${c.hidden ? '（已隐藏）' : ''}'),
                trailing: widget.onModerate == null
                    ? null
                    : TextButton(
                        onPressed: _busy ? null : () => _moderate(c),
                        child: Text(c.hidden ? '恢复' : '隐藏'),
                      ),
              );
            },
          ),
        ),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: _busy || _cursors.length == 1
                  ? null
                  : () {
                      _cursors.removeLast();
                      unawaited(_load());
                    },
              child: const Text('上一页'),
            ),
            Text('第 ${_cursors.length} 页'),
            TextButton(
              onPressed: _busy || _page?.nextCursor == null
                  ? null
                  : () {
                      _cursors.add(_page!.nextCursor);
                      unawaited(_load());
                    },
              child: const Text('下一页'),
            ),
          ],
        ),
      ],
    ),
  );
}
