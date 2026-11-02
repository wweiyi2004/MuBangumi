import 'package:flutter/material.dart';

/// Preserve navigation and drafts while pausing hidden image/animation tickers.
class RetainedTabStack extends StatelessWidget {
  const RetainedTabStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: index,
    children: [
      for (var i = 0; i < children.length; i++)
        TickerMode(enabled: i == index, child: children[i]),
    ],
  );
}
