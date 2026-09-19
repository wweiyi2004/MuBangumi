import '../navigation/app_destination.dart';
import 'dart:async';
import 'package:flutter/material.dart';

import '../core/network/community_service.dart';
import '../models/community_models.dart';
import '../widgets/community_loading.dart';
import '../widgets/community_widgets.dart';

/// Complete paginated lists, separate from the group's recent-content preview.
class CommunityGroupBrowseScreen extends StatefulWidget {
  const CommunityGroupBrowseScreen({
    super.key,
    required this.group,
    required this.service,
    this.members = false,
  });

  final CommunityGroup group;
  final CommunityService service;
  final bool members;

  @override
  State<CommunityGroupBrowseScreen> createState() =>
      _CommunityGroupBrowseScreenState();
}

class _CommunityGroupBrowseScreenState
    extends State<CommunityGroupBrowseScreen> {
  final _scroll = ScrollController();
  final _items = <Object>[];
  bool _loading = false, _hasMore = true;
  bool _failedRefresh = false;
  int _offset = 0, _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.service.accountChanges.addListener(_resetContent);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400 && _error == null) _load();
    });
    _load(refresh: true);
  }

  void _resetContent() {
    // Invalidate in-flight responses immediately; rebuild outside the caller's
    // notification/build stack, then fetch the current account from offset 0.
    _generation++;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() {
        _items.clear();
        _offset = 0;
        _hasMore = true;
        _error = null;
        _failedRefresh = false;
      });
      unawaited(_load(refresh: true));
    });
  }

  @override
  void didUpdateWidget(covariant CommunityGroupBrowseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.accountChanges.removeListener(_resetContent);
      widget.service.accountChanges.addListener(_resetContent);
    }
    if (oldWidget.service != widget.service ||
        oldWidget.group != widget.group ||
        oldWidget.members != widget.members) {
      _resetContent();
    }
  }

  String get _slug => widget.group.slug.isNotEmpty
      ? widget.group.slug
      : Uri.parse(widget.group.url).pathSegments.last;

  Future<void> _load({bool refresh = false}) async {
    if (!refresh && (_loading || !_hasMore)) return;
    final generation = refresh ? ++_generation : _generation;
    final account = widget.service.currentUsername;
    final offset = refresh ? 0 : _offset;
    setState(() {
      _loading = true;
      _error = null;
      _failedRefresh = false;
    });
    try {
      final CommunityPageResult<Object> page = widget.members
          ? await widget.service.loadGroupMembers(
              _slug,
              offset: offset,
              refresh: refresh,
            )
          : await widget.service.loadGroupTopics(
              _slug,
              offset: offset,
              refresh: refresh,
            );
      if (!mounted ||
          generation != _generation ||
          account != widget.service.currentUsername) {
        return;
      }
      setState(() {
        if (refresh) _items.clear();
        String key(Object value) => switch (value) {
          CommunityTopic topic => 'topic:${topic.id}',
          CommunityUser user => 'user:${user.id}',
          _ => throw StateError('Unknown group content'),
        };
        final seen = _items.map(key).toSet();
        _items.addAll(page.data.where((item) => seen.add(key(item))));
        final received = page.rawCount ?? page.data.length;
        _offset = offset + received;
        _hasMore = received > 0 && _offset < page.total;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _failedRefresh = refresh;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.service.accountChanges.removeListener(_resetContent);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.group.name} · ${widget.members ? '全部成员' : '全部话题'}'),
    ),
    body: RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return CommunityLoadMoreFooter(
              loading: _loading,
              hasMore: _hasMore,
              error: _error,
              onLoad: () => _load(refresh: _failedRefresh || _items.isEmpty),
            );
          }
          final item = _items[index];
          if (item is CommunityUser) {
            return ListTile(
              leading: CommunityAvatar(imageUrl: item.avatarUrl),
              title: Text(item.displayName),
              subtitle: Text('@${item.username}'),
              onTap: () => openUserProfileFromCommunity(context, item),
            );
          }
          final topic = item as CommunityTopic;
          return CommunityTopicCard(
            topic: topic,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    TopicRoute(topic: topic, service: widget.service),
              ),
            ),
          );
        },
      ),
    ),
  );
}
