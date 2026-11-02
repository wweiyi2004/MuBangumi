import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/bangumi_support.dart';
import '../core/onboarding/watched_guess.dart';
import '../core/theme/anime_icon.dart';
import '../state/watched_catalog_provider.dart';
import '../widgets/watched_intake_workspace.dart';
import '../models/bangumi_models.dart';
import '../navigation/app_destination.dart';
import '../state/session_controller.dart';
import '../widgets/subject_widgets.dart';

/// Draws one likely-watched anime at a time, then files the card onto a pile.
class WatchedIntakePage extends ConsumerStatefulWidget {
  const WatchedIntakePage({
    super.key,
    this.loadDeck,
    this.loadRelated,
    this.clock,
  });

  final Future<List<Subject>> Function()? loadDeck;
  final Future<List<RelatedSubject>> Function(int subjectId)? loadRelated;
  final DateTime Function()? clock;

  @override
  ConsumerState<WatchedIntakePage> createState() => _WatchedIntakePageState();
}

class _KeptCard {
  const _KeptCard(this.candidate, {this.through});
  final WatchedCandidate candidate;
  final int? through;
  bool get finished => through == null;
}

enum _Fly { none, pile, discard }

class _WatchedIntakePageState extends ConsumerState<WatchedIntakePage>
    with SingleTickerProviderStateMixin {
  var _ranker = WatchedGuessRanker();
  final _kept = <_KeptCard>[];
  WatchedGuess? _current;
  var _loading = true;
  var _enriching = false;
  var _round = 0;
  String? _notice;
  final _history = <({WatchedGuess guess, bool kept})>[];
  var _saving = false;
  var _askingEpisode = false;
  var _episode = 1;
  var _loadGeneration = 0;
  String? _error;
  _Fly _fly = _Fly.none;
  BuildContext? _overlayContext;
  var _leaveDialogShown = false;
  late final AnimationController _motion;
  late final CurvedAnimation _travel;
  int _savedCount = 0, _saveTotal = 0;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _travel = CurvedAnimation(parent: _motion, curve: Curves.easeInCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _loadGeneration++;
    _travel.dispose();
    _motion.dispose();
    super.dispose();
  }

  int get _deckCount {
    final id = _current?.candidate.id;
    final active =
        id != null &&
        !_ranker.owns(id) &&
        !_ranker.accepted.contains(id) &&
        !_ranker.rejected.contains(id);
    return (_ranker.remainingCount - (active ? 1 : 0)).clamp(0, 1 << 20);
  }

  void _resetForAccountChange() {
    final overlay = _overlayContext;
    if (overlay != null &&
        overlay.mounted &&
        ModalRoute.of(overlay)?.isCurrent == true) {
      Navigator.pop(overlay);
    }
    _overlayContext = null;
    _loadGeneration++;
    _motion.reset();
    _ranker = WatchedGuessRanker();
    _kept.clear();
    _history.clear();
    _round = 0;
    _current = null;
    _askingEpisode = false;
    _saving = false;
    _fly = _Fly.none;
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      sessionProvider.select(
        (state) => (state.user?.id, state.user?.username, state.phase),
      ),
      (previous, next) {
        if (previous != null && previous != next) {
          // Invalidate async work immediately, before the next frame resets UI.
          _loadGeneration++;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _resetForAccountChange();
          });
        }
      },
    );
    ref.listen(sessionProvider.select((state) => state.collections), (_, next) {
      final ids = next.map((item) => item.subjectId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ranker.excludeOwned(ids);
        _history.removeWhere((entry) => _ranker.owns(entry.guess.candidate.id));
        if (_current != null && _ranker.owns(_current!.candidate.id)) {
          setState(() => _current = _drawNext());
        }
      });
    });
    final colors = Theme.of(context).colorScheme;
    final current = _current;
    final busy = _saving || _fly != _Fly.none;
    return PopScope(
      canPop: _kept.isEmpty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving && !_leaveDialogShown) {
          unawaited(_confirmLeave());
        }
      },
      child: Scaffold(
        backgroundColor: colors.surface,
        appBar: AppBar(
          title: const Text('搬进看过的番'),
          actions: [
            IconButton(
              tooltip: '撤销上一张',
              onPressed: _history.isEmpty || busy ? null : _undoLast,
              icon: const AnimeIcon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: '换一批候选',
              onPressed: _loading || _enriching || busy ? null : _more,
              icon: const AnimeIcon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: WatchedIntakeWorkspace(
            stage: _stage(current),
            remaining: _deckCount,
            kept: _kept.length,
            enriching: _enriching && !_loading,
            notice: _loading ? '正在准备候选，稍后就能开始' : _notice,
            actions: _actions(current),
            save: FilledButton.icon(
              onPressed: _kept.isEmpty || busy ? null : _sync,
              icon: AnimeIcon(
                _saving ? Icons.hourglass_top_rounded : Icons.done_all_rounded,
                size: 18,
              ),
              label: Text(
                _saving
                    ? '已记下 $_savedCount / $_saveTotal 部'
                    : '同步 ${_kept.length} 部',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            onReview: _kept.isEmpty || busy ? null : _review,
          ),
        ),
      ),
    );
  }

  Widget _stage(WatchedGuess? current) {
    if (_loading) {
      return const WatchedIntakeLoading();
    }
    if (_error != null) {
      return WatchedIntakeMessage(
        title: '这一叠番，暂时没找到',
        detail: _error!,
        icon: Icons.wifi_off_rounded,
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (current == null) {
      if (_enriching) {
        return const WatchedIntakeLoading(label: '正在继续找番…');
      }
      return WatchedIntakeMessage(
        title: '这叠牌抽完了',
        detail: '换一批继续找，或同步已经收下的。',
        icon: Icons.auto_awesome_rounded,
        actionLabel: '再找一批',
        onAction: _more,
      );
    }
    final end = _fly == _Fly.discard
        ? const Offset(-.35, .02)
        : const Offset(.35, .04);
    final next = _ranker
        .next(count: 2)
        .where((guess) => guess.candidate.id != current.candidate.id)
        .firstOrNull;
    return WatchedIntakePreload(
      next: next?.candidate.toSubject(),
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset.zero, end: end).animate(_travel),
        child: FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0.2).animate(_travel),
          child: WatchedIntakeSwipeCard(
            key: ValueKey('intake-card-${current.candidate.id}'),
            enabled: !_saving && _fly == _Fly.none && !_askingEpisode,
            onKeep: () => unawaited(_keep(current)),
            onSkip: () => unawaited(_discard(current)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                WatchedIntakePoster(guess: current),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    tooltip: '查看条目详情',
                    onPressed: _saving || _fly != _Fly.none
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => SubjectRoute(
                                subject: current.candidate.toSubject(),
                              ),
                            ),
                          ),
                    icon: const AnimeIcon(Icons.open_in_new_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(WatchedGuess? current) {
    final busy = current == null || _saving || _fly != _Fly.none || _loading;
    if (_askingEpisode && current != null) {
      final total = current.candidate.episodeCount;
      final max = total > 0 ? total : 9999;
      return Column(
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: busy ? null : () => _editEpisode(max),
            icon: const AnimeIcon(Icons.edit_outlined, size: 16),
            label: Text(
              total > 0 ? '看到第 $_episode / $total 话' : '看到第 $_episode 话',
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              IconButton(
                onPressed: _episode <= 1
                    ? null
                    : () => setState(() => _episode--),
                icon: const AnimeIcon(Icons.remove_rounded),
              ),
              IconButton(
                onPressed: _episode >= max
                    ? null
                    : () => setState(() => _episode++),
                icon: const AnimeIcon(Icons.add_rounded),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => _askingEpisode = false),
                child: const Text('返回'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => _keep(current, through: _episode),
                child: const Text('确认'),
              ),
            ],
          ),
        ],
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final secondary = OutlinedButton.styleFrom(
      foregroundColor: scheme.onSurfaceVariant,
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    final skip = OutlinedButton(
      style: secondary,
      onPressed: busy ? null : () => _discard(current),
      child: const Text('没看过', textAlign: TextAlign.center),
    );
    final keep = FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: busy ? null : () => _keep(current),
      child: const Text('看过', textAlign: TextAlign.center),
    );
    void askEpisode() => setState(() {
      _askingEpisode = true;
      _episode = 1;
    });
    if (MediaQuery.textScalerOf(context).scale(14) > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: skip),
              const SizedBox(width: 8),
              Expanded(child: keep),
            ],
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
            ),
            onPressed: busy ? null : askEpisode,
            icon: const AnimeIcon(Icons.edit_note_rounded, size: 20),
            label: const Text('看到第几集'),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: skip),
        const SizedBox(width: 8),
        Expanded(child: keep),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: secondary,
            onPressed: busy ? null : askEpisode,
            child: const Text('看到第几集', textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }

  void _more() {
    _round++;
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = _current == null;
      _enriching = true;
      _error = null;
      _notice = null;
    });
    _ranker.excludeOwned(
      ref.read(sessionProvider).collections.map((item) => item.subjectId),
    );
    var failed = false;
    void add(List<Subject> subjects) {
      if (!mounted || generation != _loadGeneration) return;
      _ranker.addSubjects(subjects);
      setState(() {
        _current ??= _drawNext();
        if (_current != null) _loading = false;
      });
    }

    try {
      if (widget.loadDeck != null) {
        add(await widget.loadDeck!());
      } else {
        final catalog = ref.read(watchedCatalogProvider);
        add(catalog.cached);
        await for (final batch in catalog.load(_now.year, round: _round)) {
          if (!mounted || generation != _loadGeneration) return;
          failed = failed || batch.failed;
          add(batch.subjects);
        }
      }
    } catch (_) {
      failed = true;
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _loading = false;
      _enriching = false;
      if (failed && _current == null && _ranker.remainingCount == 0) {
        _error = '候选暂时没能加载，请检查网络后重试';
      } else if (failed) {
        _notice = '部分候选未能加载，可以先挑选已有的番';
      }
    });
  }

  Future<void> _keep(WatchedGuess guess, {int? through}) async {
    if (_saving ||
        _fly != _Fly.none ||
        _current?.candidate.id != guess.candidate.id) {
      return;
    }
    final generation = _loadGeneration;
    final item = guess.candidate;
    _ranker.accept(item);
    _kept.add(_KeptCard(item, through: through));
    _history.add((guess: guess, kept: true));
    setState(() => _fly = _Fly.pile);
    unawaited(_pullRelated(item.id, generation));
    if (!await _animate()) return;
    if (!mounted || generation != _loadGeneration) return;
    _askingEpisode = false;
    _current = _drawNext();
    _motion.value = 0;
    setState(() => _fly = _Fly.none);
  }

  Future<void> _discard(WatchedGuess guess) async {
    if (_saving ||
        _fly != _Fly.none ||
        _current?.candidate.id != guess.candidate.id) {
      return;
    }
    final generation = _loadGeneration;
    setState(() => _fly = _Fly.discard);
    if (!await _animate()) return;
    if (!mounted || generation != _loadGeneration) return;
    _ranker.reject(guess.candidate);
    _history.add((guess: guess, kept: false));
    _askingEpisode = false;
    _current = _drawNext();
    _motion.value = 0;
    setState(() => _fly = _Fly.none);
  }

  WatchedGuess? _drawNext() {
    final next = _ranker.next(count: 1);
    return next.isEmpty ? null : next.first;
  }

  Future<bool> _animate() async {
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      return true;
    }
    try {
      await _motion.forward(from: 0).orCancel;
      return true;
    } on TickerCanceled {
      return false;
    }
  }

  void _undoLast() {
    if (_history.isEmpty || _saving || _fly != _Fly.none) return;
    _history.removeWhere((entry) => _ranker.owns(entry.guess.candidate.id));
    if (_history.isEmpty) {
      setState(() {});
      return;
    }
    final last = _history.removeLast();
    if (last.kept) {
      _kept.removeWhere((card) => card.candidate.id == last.guess.candidate.id);
      _ranker.undoAccept(last.guess.candidate.id);
    } else {
      _ranker.undoReject(last.guess.candidate.id);
    }
    _askingEpisode = false;
    setState(() => _current = last.guess);
  }

  Future<void> _review() async {
    final generation = _loadGeneration;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        _overlayContext = context;
        return StatefulBuilder(
          builder: (context, updateSheet) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    title: Text('本次待同步清单'),
                    subtitle: Text('确认同步后才会写入收藏，移除不会修改官网记录。'),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _kept.length,
                      itemBuilder: (context, index) {
                        final card = _kept[index];
                        return ListTile(
                          leading: SubjectCover(
                            subject: card.candidate.toSubject(),
                            width: 38,
                            height: 54,
                            borderRadius: 8,
                          ),
                          title: Text(card.candidate.displayName),
                          subtitle: Text(
                            card.finished ? '整部看过' : '看到第 ${card.through} 话',
                          ),
                          trailing: IconButton(
                            tooltip: '移出本次清单',
                            icon: const AnimeIcon(Icons.close_rounded),
                            onPressed: () {
                              if (!mounted || generation != _loadGeneration) {
                                Navigator.pop(context);
                                return;
                              }
                              _ranker.undoAccept(card.candidate.id);
                              _history.removeWhere(
                                (entry) =>
                                    entry.guess.candidate.id ==
                                    card.candidate.id,
                              );
                              setState(() => _kept.remove(card));
                              updateSheet(() {});
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _overlayContext = null;
  }

  Future<void> _confirmLeave() async {
    final generation = _loadGeneration;
    _leaveDialogShown = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) {
        _overlayContext = context;
        return AlertDialog(
          title: const Text('还有未同步的挑选'),
          content: Text('本次挑选的 ${_kept.length} 部番还没有记入收藏。离开会放弃这些挑选。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续挑选'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃并离开'),
            ),
          ],
        );
      },
    );
    _overlayContext = null;
    _leaveDialogShown = false;
    if (discard != true || !mounted || generation != _loadGeneration) return;
    setState(() => _kept.clear());
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _editEpisode(int max) async {
    final generation = _loadGeneration;
    var value = '$_episode';
    String? error;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) {
        _overlayContext = context;
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('记到看到的那一集'),
            content: TextFormField(
              initialValue: value,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: '已看话数', errorText: error),
              onChanged: (text) => value = text,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final episode = int.tryParse(value.trim());
                  if (episode == null || episode < 1 || episode > max) {
                    update(() => error = '请输入 1–$max 之间的整数');
                    return;
                  }
                  Navigator.pop(context, episode);
                },
                child: const Text('应用话数'),
              ),
            ],
          ),
        );
      },
    );
    _overlayContext = null;
    if (selected != null && mounted && generation == _loadGeneration) {
      setState(() => _episode = selected);
    }
  }

  Future<void> _pullRelated(int id, int generation) async {
    try {
      final related = widget.loadRelated == null
          ? await ref.read(bangumiApiProvider).getRelatedSubjects(id)
          : await widget.loadRelated!(id);
      if (!mounted ||
          generation != _loadGeneration ||
          !_ranker.accepted.contains(id)) {
        return;
      }
      _ranker.noteRelated(id, [
        for (final subject in related)
          if (subject.type == SubjectType.anime)
            WatchedCandidate(
              id: subject.id,
              name: subject.name,
              nameCn: subject.nameCn,
              imageUrl: subject.imageUrl,
            ),
      ]);
      if (!_askingEpisode && _current == null) _current = _drawNext();
      setState(() {});
    } catch (_) {}
  }

  Future<void> _sync() async {
    final generation = _loadGeneration;
    final cards = List<_KeptCard>.of(_kept);
    if (cards.isEmpty || _saving || _fly != _Fly.none) return;
    final notifier = ref.read(sessionProvider.notifier);
    final account = notifier.batchAccount;
    if (account == null) {
      showAppMessage(context, '登录后才能同步观看记录，当前挑选尚未写入收藏');
      return;
    }
    final revisions = {
      for (final card in cards)
        card.candidate.id: notifier.collectionMutationRevision(
          card.candidate.id,
        ),
    };
    setState(() {
      _saving = true;
      _savedCount = 0;
      _saveTotal = cards.length;
    });
    String? error;
    var savedFinished = 0;
    var savedPartial = 0;
    for (final card in cards) {
      error = await notifier.changeCollection(
        card.candidate.toSubject(),
        card.finished ? CollectionType.done : CollectionType.doing,
        completeEpisodesWhenDone: card.finished,
        watchedThrough: card.through,
        expectedAccount: account,
        expectedRevision: revisions[card.candidate.id],
        deferSync: true,
      );
      if (!mounted || generation != _loadGeneration) return;
      if (error != null) break;
      if (card.finished) {
        savedFinished++;
      } else {
        savedPartial++;
      }
      _kept.remove(card);
      _history.removeWhere(
        (entry) => entry.guess.candidate.id == card.candidate.id,
      );
      setState(() => _savedCount++);
    }
    if ((savedFinished > 0 || savedPartial > 0) &&
        mounted &&
        notifier.isCurrentBatchAccount(account)) {
      // Edits are already durably queued. Network acknowledgement must not
      // hold the picker or prevent returning to another page.
      unawaited(notifier.syncPendingChanges().catchError((Object _) {}));
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() => _saving = false);
    final summary =
        error ??
        '已在本机记下 $savedFinished 部看过${savedPartial > 0 ? '，$savedPartial 部记到看到的那一集' : ''}，正在后台同步。';
    showAppMessage(context, summary);
  }
}
