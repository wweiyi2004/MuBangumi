import 'package:flutter/material.dart';

/// Shared breakpoints and spacing for phone / tablet / desktop.
class AppLayout {
  AppLayout._();

  static const double phone = 600;
  static const double tablet = 900;
  static const double wide = 1100;

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isPhone(BuildContext context) => widthOf(context) < phone;

  static bool isCompact(BuildContext context) => widthOf(context) < 720;

  static bool isDesktop(BuildContext context) => widthOf(context) >= tablet;

  /// Horizontal page padding: tighter on phones.
  static double pagePadding(BuildContext context) {
    final w = widthOf(context);
    if (w < 360) return 12;
    if (w < phone) return 14;
    if (w < tablet) return 18;
    return 20;
  }

  static EdgeInsets pageInsets(
    BuildContext context, {
    double top = 20,
    double bottom = 56,
  }) {
    final h = pagePadding(context);
    final narrow = isPhone(context);
    return EdgeInsets.fromLTRB(
      h,
      narrow ? (top * 0.7).clamp(10, top) : top,
      h,
      narrow ? (bottom * 0.75).clamp(36, bottom) : bottom,
    );
  }

  static double sectionGap(BuildContext context) => isPhone(context) ? 14 : 18;

  static double pageTopPadding(BuildContext context) =>
      isPhone(context) ? 16 : 24;

  static double blockGap(BuildContext context) => isPhone(context) ? 20 : 28;

  static TextStyle? pageTitleStyle(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return isPhone(context) ? theme.headlineMedium : theme.headlineLarge;
  }

  static TextStyle? sectionTitleStyle(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return isPhone(context) ? theme.titleLarge : theme.headlineMedium;
  }

  /// Five short labels stay visible so destinations are recognizable.
  static NavigationDestinationLabelBehavior navLabelBehavior(
    BuildContext context,
  ) {
    return NavigationDestinationLabelBehavior.alwaysShow;
  }

  static double navHeight(BuildContext context) {
    return MediaQuery.textScalerOf(context).scale(12) > 18 ? 88 : 72;
  }
}

/// Scrollable page scaffold content with consistent max width + padding.
class AppPageBody extends StatelessWidget {
  const AppPageBody({
    super.key,
    required this.child,
    this.maxWidth = 1220,
    this.padding,
    this.controller,
    this.physics,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      physics: physics ?? const AlwaysScrollableScrollPhysics(),
      padding: padding ?? AppLayout.pageInsets(context),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
