import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/background_controller.dart';
import '../state/system_appearance_controller.dart';

/// One shared renderer for the app and its live settings preview.
class BackgroundWallpaper extends StatelessWidget {
  const BackgroundWallpaper({
    super.key,
    required this.settings,
    required this.child,
  });
  final AppBackgroundSettings settings;
  final Widget child;

  static Color veil(ThemeData theme, AppBackgroundSettings settings) => theme
      .colorScheme
      .surface
      .withValues(alpha: .82 + settings.dim.clamp(0, .75) / .75 * .12);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!settings.isActive || MediaQuery.highContrastOf(context)) {
      return ColoredBox(color: theme.colorScheme.surface, child: child);
    }
    return LayoutBuilder(
      builder: (context, size) {
        final decodedWidth =
            (size.maxWidth * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(1, 2560);
        final image = Image(
          excludeFromSemantics: true,
          image: ResizeImage(
            FileImage(File(settings.imagePath!)),
            width: decodedWidth,
            allowUpscaling: false,
          ),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) =>
              ColoredBox(color: theme.colorScheme.surface),
        );
        final filtered = ImageFiltered(
          enabled: settings.blurSigma > 0,
          imageFilter: ImageFilter.blur(
            sigmaX: settings.blurSigma,
            sigmaY: settings.blurSigma,
            tileMode: TileMode.mirror,
          ),
          child: RepaintBoundary(child: image),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: IgnorePointer(child: RepaintBoundary(child: filtered)),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: veil(theme, settings)),
              ),
            ),
            child,
          ],
        );
      },
    );
  }
}

class AppBackgroundHost extends ConsumerWidget {
  const AppBackgroundHost({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(effectiveBackgroundProvider);
    if (!settings.isActive || MediaQuery.highContrastOf(context)) return child;
    return BackgroundWallpaper(settings: settings, child: child);
  }
}

/// Translucency belongs to navigation; content, forms and overlays stay solid.
ThemeData applyBackgroundTheme(ThemeData base, AppBackgroundSettings settings) {
  if (!settings.isActive) return base;
  final scheme = base.colorScheme;
  final navigation = scheme.surface.withValues(alpha: settings.panelOpacity);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    // Keep canvas opaque: menus and anonymous Material surfaces need a backplate.
    canvasColor: scheme.surface,
    cardTheme: base.cardTheme.copyWith(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: navigation,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: navigation,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      backgroundColor: navigation,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: scheme.surface,
      modalBackgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    drawerTheme: base.drawerTheme.copyWith(backgroundColor: scheme.surface),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: scheme.surfaceContainer,
    ),
    // Retain accessible selected/unselected chip foreground/background pairs.
  );
}

ThemeData highContrastBackgroundTheme(ThemeData base, SystemAppearance system) {
  final dark = base.brightness == Brightness.dark;
  final background = Color(
    system.background ?? (dark ? 0xFF000000 : 0xFFFFFFFF),
  );
  final foreground = Color(
    system.foreground ?? (dark ? 0xFFFFFFFF : 0xFF000000),
  );
  final primary = Color(system.highlight ?? (dark ? 0xFFFFFF00 : 0xFF000080));
  final onPrimary = Color(
    system.onHighlight ?? (dark ? 0xFF000000 : 0xFFFFFFFF),
  );
  final scheme = base.colorScheme.copyWith(
    surface: background,
    onSurface: foreground,
    onSurfaceVariant: foreground,
    surfaceContainerLowest: background,
    surfaceContainerLow: background,
    surfaceContainer: background,
    surfaceContainerHigh: background,
    surfaceContainerHighest: background,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primary,
    onPrimaryContainer: onPrimary,
    outline: foreground,
    outlineVariant: foreground,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    textTheme: base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: background,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: background,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: background,
      modalBackgroundColor: background,
      surfaceTintColor: Colors.transparent,
    ),
    drawerTheme: base.drawerTheme.copyWith(backgroundColor: background),
    popupMenuTheme: base.popupMenuTheme.copyWith(color: background),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: background,
      indicatorColor: primary,
    ),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      backgroundColor: background,
      indicatorColor: primary,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: background,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: foreground),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: background,
      selectedColor: primary,
      labelStyle: base.chipTheme.labelStyle?.copyWith(color: foreground),
      secondaryLabelStyle: base.chipTheme.secondaryLabelStyle?.copyWith(
        color: onPrimary,
      ),
      checkmarkColor: onPrimary,
    ),
  );
}

/// Shared navigation material over the already blurred wallpaper.
class GlassPanel extends ConsumerWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 18,
    this.padding,
  });
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(backgroundThemeSettingsProvider);
    final scheme = Theme.of(context).colorScheme;
    final active = settings.isActive && !MediaQuery.highContrastOf(context);
    return Material(
      color: active
          ? scheme.surface.withValues(alpha: settings.panelOpacity)
          : scheme.surface,
      borderRadius: BorderRadius.circular(borderRadius),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}
