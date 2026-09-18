import 'package:flutter/material.dart';
import '../../../models/bangumi_models.dart';

class SubjectEpisodeGrid extends StatefulWidget {
  const SubjectEpisodeGrid({
    super.key,
    required this.episodes,
    required this.episodeTypes,
    required this.updatingEpisodes,
    required this.enabled,
    required this.onTap,
  });

  final List<Episode> episodes;
  final Map<int, int> episodeTypes;
  final Set<int> updatingEpisodes;
  final bool enabled;
  final void Function(Episode episode, bool watched) onTap;

  @override
  State<SubjectEpisodeGrid> createState() => _EpisodeGridState();
}

class _EpisodeGridState extends State<SubjectEpisodeGrid> {
  static const _pageSize = 60;
  int _visibleCount = _pageSize;

  @override
  void didUpdateWidget(covariant SubjectEpisodeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodes.length != widget.episodes.length) {
      _visibleCount = _pageSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Prefer ~5–7 cells per row on phones, keep ≥44 touch height.
        final target = width < 420
            ? 5.0
            : width < 600
            ? 6.0
            : 8.0;
        final spacing = width < 420 ? 7.0 : 9.0;
        final cellW = ((width - spacing * (target - 1)) / target).clamp(
          48.0,
          64.0,
        );
        final cellH = width < 420 ? 42.0 : 44.0;
        final visibleCount = _visibleCount < widget.episodes.length
            ? _visibleCount
            : widget.episodes.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final episode in widget.episodes.take(visibleCount))
                  Tooltip(
                    message: episode.displayName,
                    child: SizedBox(
                      width: cellW,
                      height: cellH,
                      child: widget.episodeTypes[episode.id] == 2
                          ? FilledButton(
                              onPressed:
                                  widget.enabled &&
                                      !widget.updatingEpisodes.contains(
                                        episode.id,
                                      )
                                  ? () => widget.onTap(episode, true)
                                  : null,
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                textStyle: TextStyle(
                                  fontSize: width < 380 ? 13 : 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: Text(_episodeNumber(episode.number)),
                            )
                          : OutlinedButton(
                              onPressed:
                                  widget.enabled &&
                                      !widget.updatingEpisodes.contains(
                                        episode.id,
                                      )
                                  ? () => widget.onTap(episode, false)
                                  : null,
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                textStyle: TextStyle(
                                  fontSize: width < 380 ? 13 : 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: Text(_episodeNumber(episode.number)),
                            ),
                    ),
                  ),
              ],
            ),
            if (visibleCount < widget.episodes.length) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    final next = _visibleCount + _pageSize;
                    _visibleCount = next < widget.episodes.length
                        ? next
                        : widget.episodes.length;
                  }),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    '继续显示（$visibleCount / ${widget.episodes.length}）',
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _episodeNumber(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
}
