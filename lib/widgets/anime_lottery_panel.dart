import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/recommend/anime_lottery.dart';
import '../core/theme/anime_icon.dart';
import '../models/anime_lottery.dart';
import '../models/bangumi_models.dart';
import '../models/library_batch.dart';
import '../navigation/app_destination.dart';
import '../state/session_controller.dart';
import '../state/recommendation_feedback_controller.dart';
import 'subject_widgets.dart';

class AnimeLotteryPanel extends ConsumerStatefulWidget {
  const AnimeLotteryPanel({super.key});
  @override
  ConsumerState<AnimeLotteryPanel> createState() => _AnimeLotteryPanelState();
}

class _AnimeLotteryPanelState extends ConsumerState<AnimeLotteryPanel> {
  final _lottery = AnimeLottery();
  int _generation = 0;
  bool _busy = false;
  String? _message;
  Subject? _result;
  AnimePrize? _prize;
  LibraryBatchAccount? _owner;

  @override
  void initState() {
    super.initState();
    ref.listenManual(sessionProvider, (previous, next) {
      if (!mounted ||
          (previous?.user?.id == next.user?.id &&
              (_owner == null ||
                  ref
                      .read(sessionProvider.notifier)
                      .isCurrentBatchAccount(_owner!)))) {
        return;
      }
      _generation++;
      setState(() {
        _result = null;
        _message = null;
        _busy = false;
        _owner = null;
      });
    });
  }

  Future<void> _draw(AnimePrize prize) async {
    if (_busy) return;
    final session = ref.read(sessionProvider.notifier);
    final account = session.batchAccount;
    if (account == null) {
      setState(() => _message = '登录并同步收藏后，抽一部还没看过的番');
      return;
    }
    final generation = ++_generation;
    bool current() =>
        mounted &&
        generation == _generation &&
        session.isCurrentBatchAccount(account);
    final feedback = ref.read(recommendationFeedbackProvider(account.userId));
    if (!feedback.ready || feedback.loading) return;
    setState(() {
      _busy = true;
      _message = '正在翻找未看过的番…';
      _result = null;
      _owner = account;
      _prize = prize;
    });
    try {
      final api = ref.read(bangumiApiProvider);
      final snapshot = ref.read(sessionProvider);
      final remote =
          snapshot.collectionCoverage?.isComplete == true &&
              !snapshot.isUsingCachedCollections
          ? snapshot.collections
          : await api.withRequestGuard(
              current,
              () => api.getUserCollections(
                account.username,
                subjectType: SubjectType.anime,
                onPage: (_) async => current(),
              ),
            );
      if (!current()) return;
      final result = await _lottery.draw(
        prize: prize,
        fetch: (offset, limit) => api.withRequestGuard(
          current,
          () => api.getAnimeLotteryPage(prize, offset: offset, limit: limit),
        ),
        isCurrent: current,
        excludedIds: () => {
          ...AnimeLottery.watchedIds(remote),
          ...AnimeLottery.watchedIds(ref.read(sessionProvider).collections),
          ...ref
              .read(recommendationFeedbackProvider(account.userId))
              .hidden
              .keys,
        },
      );
      if (!current()) return;
      setState(() {
        _result = result;
        _message = result == null
            ? '这次没有抽到符合条件的未看作品，再抽一次试试吧'
            : '抽中了！${prize.description}，下一部就试试它吧';
      });
    } catch (_) {
      if (current()) setState(() => _message = '抽签暂时没能完成，请稍后重试');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionProvider);
    final feedback = ref.watch(
      recommendationFeedbackProvider(state.user?.id ?? 0),
    );
    final scheme = Theme.of(context).colorScheme;
    final result = _result;
    final current =
        _owner != null &&
        ref.read(sessionProvider.notifier).isCurrentBatchAccount(_owner!);
    final visible =
        current &&
        result != null &&
        !AnimeLottery.watchedIds(state.collections).contains(result.id) &&
        !feedback.hidden.containsKey(result.id);
    return Container(
      key: const Key('anime-lottery-panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: .5),
            scheme.secondaryContainer.withValues(alpha: .35),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimeIcon(Icons.casino_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '抽一部番',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '公共评分筛选 · 排除看过、在看、搁置与抛弃的作品',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final prize in AnimePrize.values) ...[
                if (prize == AnimePrize.bad) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _busy || !feedback.ready || feedback.loading
                        ? null
                        : () => _draw(prize),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(prize.label, textAlign: TextAlign.center),
                        Text(
                          prize.description,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (visible) ...[
            const SizedBox(height: 12),
            SubjectTile(
              subject: result,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SubjectRoute(subject: result),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _draw(_prize!),
                icon: const AnimeIcon(Icons.refresh_rounded, size: 18),
                label: const Text('再抽一部'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
