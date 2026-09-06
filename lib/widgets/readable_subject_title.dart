import 'package:flutter/material.dart';

/// Compact titles retain an accessible, selectable full-name view.
class ReadableSubjectTitle extends StatelessWidget {
  const ReadableSubjectTitle(
    this.title, {
    super.key,
    this.style,
    this.maxLines = 3,
    this.textAlign,
  });

  final String title;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
      final painter = TextPainter(
        text: TextSpan(text: title, style: effectiveStyle),
        maxLines: maxLines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final clipped =
          painter.didExceedMaxLines ||
          (constraints.hasBoundedHeight &&
              painter.height > constraints.maxHeight);
      final visibleLines = constraints.hasBoundedHeight
          ? (constraints.maxHeight / painter.preferredLineHeight).floor().clamp(
              1,
              maxLines,
            )
          : maxLines;
      painter.dispose();
      final text = Text(
        title,
        style: style,
        maxLines: visibleLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
      );
      if (!clipped) return text;
      return Tooltip(
        message: title,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          hint: '查看完整名称',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showFullTitle(context),
            child: text,
          ),
        ),
      );
    },
  );

  void _showFullTitle(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('完整名称', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 12),
                SelectableText(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
