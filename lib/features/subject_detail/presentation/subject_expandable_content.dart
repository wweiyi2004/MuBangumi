import 'package:flutter/material.dart';

class SubjectExpandableText extends StatefulWidget {
  const SubjectExpandableText({
    super.key,
    required this.text,
    this.style,
    this.collapsedLines = 5,
  });

  final String text;
  final TextStyle? style;
  final int collapsedLines;

  @override
  State<SubjectExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<SubjectExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: widget.collapsedLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflow = painter.didExceedMaxLines;
        // Measurement-only painter: release native text layout resources
        // immediately instead of leaking one per rebuild.
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : widget.collapsedLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (overflow)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  foregroundColor: scheme.primary,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '展开全部'),
              ),
          ],
        );
      },
    );
  }
}

class SubjectExpandableItemList extends StatefulWidget {
  const SubjectExpandableItemList({
    super.key,
    required this.itemCount,
    required this.previewCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final int previewCount;
  final Widget Function(int index) itemBuilder;

  @override
  State<SubjectExpandableItemList> createState() => _ExpandableItemListState();
}

class _ExpandableItemListState extends State<SubjectExpandableItemList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    final showAll = _expanded || widget.itemCount <= widget.previewCount;
    final count = showAll ? widget.itemCount : widget.previewCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) widget.itemBuilder(i),
        if (widget.itemCount > widget.previewCount)
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(_expanded ? '收起' : '展开全部 ${widget.itemCount} 项'),
            ),
          ),
      ],
    );
  }
}
