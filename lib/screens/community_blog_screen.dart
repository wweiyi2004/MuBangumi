import '../state/service_providers.dart';
import '../navigation/app_destination.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/network/community_service.dart';
import '../models/community_models.dart';
import '../widgets/community_composer.dart';
import '../widgets/community_loading.dart';
import '../widgets/community_rich_content.dart';
import '../widgets/community_widgets.dart';

Future<bool> showBlogEditor(
  BuildContext context,
  CommunityService service, {
  CommunityBlog? original,
  CommunityTokenProvider? tokenProvider,
}) {
  final identity = service.identityRevision;
  final metadata = CommunityBlogDraft(
    tags: original?.tags ?? [],
    isPublic: original?.isPublic ?? true,
  );
  return showCommunityComposer(
    context,
    heading: original == null ? '发布日志' : '编辑日志',
    requireTitle: true,
    initialTitle: original?.title ?? '',
    initialContent: original?.content ?? '',
    maxLength: 100000,
    blogDraft: metadata,
    submitLabel: original == null ? '发布' : '保存',
    requireVerification: original == null,
    tokenProvider: tokenProvider,
    draftKey: communityDraftKey(service.currentUsername, [
      'blog-v1',
      original?.id ?? 'new',
    ]),
    isAccountCurrent: () =>
        service.isAuthenticated && service.identityRevision == identity,
    onSubmit: (title, content, token) => service.saveBlog(
      original: original,
      title: title,
      content: content,
      tags: metadata.tags,
      isPublic: metadata.isPublic,
      turnstileToken: token,
    ),
  );
}

class CommunityBlogListScreen extends StatefulWidget {
  const CommunityBlogListScreen({
    super.key,
    this.username,
    this.service,
    this.tokenProvider,
    this.embedded = false,
    this.usePrimaryScrollController = false,
  });
  final String? username;
  final CommunityService? service;
  final CommunityTokenProvider? tokenProvider;
  final bool embedded;
  final bool usePrimaryScrollController;
  @override
  State<CommunityBlogListScreen> createState() =>
      _CommunityBlogListScreenState();
}

class _CommunityBlogListScreenState extends State<CommunityBlogListScreen> {
  late final CommunityService _service =
      widget.service ?? communityServiceFor(context);
  String get _username => widget.username ?? _service.currentUsername ?? '';
  final _scroll = ScrollController();
  final _items = <CommunityBlog>[];
  int _offset = 0, _generation = 0;
  bool _busy = false, _hasMore = true, _retryRefresh = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _service.accountChanges.addListener(_reset);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400 && _error == null) {
        unawaited(_load());
      }
    });
    unawaited(_load(refresh: true));
  }

  void _reset() {
    _generation++;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() {
        _items.clear();
        _offset = 0;
        _hasMore = true;
        _error = null;
      });
      unawaited(_load(refresh: true));
    });
  }

  Future<void> _load({bool refresh = false}) async {
    if (!refresh && (_busy || !_hasMore)) return;
    final generation = refresh ? ++_generation : _generation;
    final username = _username;
    if (username.isEmpty) {
      setState(() {
        _busy = false;
        _hasMore = false;
      });
      return;
    }
    final offset = refresh ? 0 : _offset;
    setState(() {
      _busy = true;
      _error = null;
      _retryRefresh = false;
    });
    try {
      final page = await _service.loadUserBlogs(
        username,
        offset: offset,
        refresh: refresh,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (refresh) _items.clear();
        final known = _items.map((item) => item.id).toSet();
        _items.addAll(page.data.where((item) => known.add(item.id)));
        final count = page.rawCount ?? page.data.length;
        _offset = offset + count;
        _hasMore = count > 0 && _offset < page.total;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$error';
          _retryRefresh = refresh;
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final identity = _service.identityRevision;
    final sent = await showBlogEditor(
      context,
      _service,
      tokenProvider: widget.tokenProvider,
    );
    if (sent && mounted && identity == _service.identityRevision) {
      await _load(refresh: true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _service.accountChanges.removeListener(_reset);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : AppBar(
            title: Text(
              widget.username == null ? '我的日志' : '${widget.username} 的日志',
            ),
          ),
    floatingActionButton:
        _service.isAuthenticated &&
            _username.toLowerCase() == _service.currentUsername?.toLowerCase()
        ? FloatingActionButton.extended(
            onPressed: _create,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('写日志'),
          )
        : null,
    body: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (widget.usePrimaryScrollController &&
            notification.depth == 0 &&
            notification is ScrollUpdateNotification &&
            notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 400 &&
            _error == null) {
          unawaited(_load());
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: ListView.builder(
          key: PageStorageKey('profile-blogs-$_username'),
          primary: widget.usePrimaryScrollController,
          controller: widget.usePrimaryScrollController ? null : _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          itemCount: _items.length + 1,
          itemBuilder: (context, index) {
            if (index == _items.length) {
              return Column(
                children: [
                  if (!_busy && _error == null && _items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(_username.isEmpty ? '请登录查看自己的日志' : '还没有日志'),
                    ),
                  CommunityLoadMoreFooter(
                    loading: _busy,
                    hasMore: _hasMore,
                    error: _error,
                    onLoad: () =>
                        _load(refresh: _retryRefresh || _items.isEmpty),
                  ),
                ],
              );
            }
            final blog = _items[index];
            return Card(
              child: ListTile(
                title: Text(blog.title),
                subtitle: Text(
                  '${blog.isPublic ? '公开' : '仅好友可见'} · ${blog.replyCount} 条评论',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CommunityBlogScreen(
                        blogId: blog.id,
                        service: _service,
                      ),
                    ),
                  );
                  if (mounted) await _load(refresh: true);
                },
              ),
            );
          },
        ),
      ),
    ),
  );
}

class CommunityBlogScreen extends StatefulWidget {
  const CommunityBlogScreen({super.key, required this.blogId, this.service});
  final int blogId;
  final CommunityService? service;
  @override
  State<CommunityBlogScreen> createState() => _CommunityBlogScreenState();
}

class _CommunityBlogScreenState extends State<CommunityBlogScreen> {
  late final CommunityService _service =
      widget.service ?? communityServiceFor(context);
  CommunityBlog? _blog;
  bool _loading = true;
  int _generation = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _service.accountChanges.addListener(_reset);
    unawaited(_load());
  }

  void _reset() {
    _generation++;
    scheduleMicrotask(() {
      if (mounted) {
        setState(() => _blog = null);
        unawaited(_load(refresh: true));
      }
    });
  }

  Future<void> _load({bool refresh = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final blog = await _service.loadBlog(widget.blogId, refresh: refresh);
      if (mounted && generation == _generation) setState(() => _blog = blog);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _edit() async {
    final blog = _blog;
    if (blog == null || !_service.canEditBlog(blog)) return;
    final identity = _service.identityRevision;
    final sent = await showBlogEditor(context, _service, original: blog);
    if (sent && mounted && identity == _service.identityRevision) {
      await _load(refresh: true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _service.accountChanges.removeListener(_reset);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blog = _blog;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          if (blog != null && _service.canEditBlog(blog))
            IconButton(
              onPressed: _loading ? null : _edit,
              tooltip: '编辑日志',
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            if (_loading && blog == null)
              const Center(child: CircularProgressIndicator()),
            if (_error != null)
              CommunityErrorView(
                message: _error!,
                onRetry: () => _load(refresh: true),
              ),
            if (blog != null) ...[
              Text(
                blog.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                '${blog.user.displayName} · ${blog.isPublic ? '公开' : '仅好友可见'}',
              ),
              if (blog.tags.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final tag in blog.tags) Chip(label: Text(tag)),
                  ],
                ),
              const Divider(height: 28),
              CommunityRichContent(blog.content),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.forum_outlined),
                label: Text('评论 · ${blog.replyCount}'),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TopicRoute(
                        service: _service,
                        topic: CommunityTopic(
                          id: blog.id,
                          kind: CommunityTopicKind.blog,
                          title: blog.title,
                          author: blog.user.displayName,
                          url: 'https://bgm.tv/blog/${blog.id}',
                          webUrl: 'https://bgm.tv/blog/${blog.id}',
                        ),
                      ),
                    ),
                  );
                  if (mounted) await _load(refresh: true);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
