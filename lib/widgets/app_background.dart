import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/background_controller.dart';

/// Full-app layered wallpaper shell:
/// photo → soft image blur → dim gradient → frosted veil → sharp UI.
class AppBackgroundHost extends ConsumerWidget {
  const AppBackgroundHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(backgroundSettingsProvider);
    if (!settings.isActive) return child;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final file = File(settings.imagePath!);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1 — user photo
        Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => ColoredBox(
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
        // Layer 2 — dreamy soft blur of the same photo (depth)
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.55,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: (settings.blur * 0.35).clamp(2, 18),
                  sigmaY: (settings.blur * 0.35).clamp(2, 18),
                  tileMode: TileMode.decal,
                ),
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        // Layer 3 — readability dim + vignette
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(
                    alpha: settings.dim * (isDark ? 1.05 : 0.85),
                  ),
                  Colors.black.withValues(
                    alpha: settings.dim * (isDark ? 0.75 : 0.55),
                  ),
                  Colors.black.withValues(
                    alpha: settings.dim * (isDark ? 1.15 : 0.95),
                  ),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
        ),
        // Layer 4 — frosted glass veil (blurs wallpaper behind UI)
        if (settings.blur > 0.5)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: settings.blur,
                    sigmaY: settings.blur,
                  ),
                  child: ColoredBox(
                    color: (isDark ? Colors.black : Colors.white).withValues(
                      alpha: isDark ? 0.10 : 0.08,
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Layer 5 — app content (sharp)
        child,
      ],
    );
  }
}

/// Theme tweaks so scaffolds / cards / bars sit on the glass stack.
ThemeData applyBackgroundTheme(ThemeData base, AppBackgroundSettings settings) {
  if (!settings.isActive) return base;
  final scheme = base.colorScheme;
  final isDark = base.brightness == Brightness.dark;
  final glass = settings.glass;
  final panel = scheme.surface.withValues(alpha: glass);
  final panelLow = scheme.surfaceContainerLow.withValues(
    alpha: (glass + 0.08).clamp(0.2, 0.88),
  );
  final border = (isDark ? Colors.white : Colors.black).withValues(
    alpha: isDark ? 0.10 : 0.06,
  );

  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: panel.withValues(alpha: (glass + 0.12).clamp(0.3, 0.92)),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: panelLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: panel.withValues(alpha: glass * 0.85),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: panel.withValues(alpha: (glass + 0.1).clamp(0.25, 0.9)),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: panel.withValues(alpha: (glass + 0.15).clamp(0.35, 0.95)),
      surfaceTintColor: Colors.transparent,
    ),
    drawerTheme: base.drawerTheme.copyWith(
      backgroundColor: panel.withValues(alpha: (glass + 0.12).clamp(0.35, 0.95)),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: panelLow.withValues(alpha: (glass + 0.05).clamp(0.25, 0.9)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: panelLow,
      selectedColor: scheme.primary.withValues(alpha: 0.85),
      side: BorderSide(color: border),
    ),
  );
}

/// Optional local frosted panel for custom surfaces.
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
    final settings = ref.watch(backgroundSettingsProvider);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!settings.isActive) {
      return Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(borderRadius),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: (settings.blur * 0.65).clamp(8, 28),
          sigmaY: (settings.blur * 0.65).clamp(8, 28),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: settings.glass),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: isDark ? 0.12 : 0.06,
              ),
            ),
          ),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}
