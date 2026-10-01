import 'package:flutter/material.dart';
import 'app_tokens.dart';
import 'app_menu_theme.dart';

class CustomColors {
  const CustomColors({
    this.primary = AppPalette.bangumiPink,
    this.secondary = const Color(0xFF38A89D),
    this.lightCanvas = const Color(0xFFFBFAF9),
    this.darkCanvas = const Color(0xFF101014),
  });
  final Color primary, secondary, lightCanvas, darkCanvas;
  Map<String, dynamic> toJson() => {
    'primary': primary.toARGB32(),
    'secondary': secondary.toARGB32(),
    'lightCanvas': lightCanvas.toARGB32(),
    'darkCanvas': darkCanvas.toARGB32(),
  };
  factory CustomColors.fromJson(Map<String, dynamic> json) {
    Color read(String key) {
      final value = json[key];
      if (value is! int || value < 0xFF000000 || value > 0xFFFFFFFF) {
        throw const FormatException('配色数据无效');
      }
      return Color(value);
    }

    return CustomColors(
      primary: read('primary'),
      secondary: read('secondary'),
      lightCanvas: read('lightCanvas'),
      darkCanvas: read('darkCanvas'),
    );
  }
}

class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors(this.accent);
  final Color accent;
  static Color of(BuildContext context) =>
      Theme.of(context).extension<BrandColors>()?.accent ??
      AppPalette.bangumiPink;
  @override
  BrandColors copyWith({Color? accent}) => BrandColors(accent ?? this.accent);
  @override
  BrandColors lerp(covariant BrandColors? other, double t) =>
      BrandColors(Color.lerp(accent, other?.accent, t)!);
}

Color readableOn(Color background) =>
    background.computeLuminance() > .179 ? Colors.black : Colors.white;

ThemeData applyCustomColors(ThemeData base, CustomColors? colors) {
  if (colors == null) return base;
  final dark = base.brightness == Brightness.dark;
  final canvas = dark ? colors.darkCanvas : colors.lightCanvas;
  final derived = ColorScheme.fromSeed(
    seedColor: colors.primary,
    brightness: base.brightness,
  );
  final secondary = ColorScheme.fromSeed(
    seedColor: colors.secondary,
    brightness: base.brightness,
  );
  // User-defined backgrounds also need readable text on every derived surface.
  final ink = readableOn(canvas);
  final tint = ink == Colors.black ? Colors.white : Colors.black;
  final surface = Color.alphaBlend(tint.withValues(alpha: .04), canvas);
  Color contrast(Color proposed) {
    final a = proposed.computeLuminance(), b = canvas.computeLuminance();
    return ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05) >= 4.5
        ? proposed
        : ink;
  }

  final scheme = derived.copyWith(
    primary: contrast(derived.primary),
    onPrimary: readableOn(contrast(derived.primary)),
    secondary: contrast(secondary.primary),
    onSecondary: readableOn(contrast(secondary.primary)),
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: ink,
    surfaceContainerLowest: canvas,
    surfaceContainerLow: surface,
    surfaceContainer: Color.alphaBlend(tint.withValues(alpha: .07), canvas),
    surfaceContainerHigh: Color.alphaBlend(tint.withValues(alpha: .10), canvas),
    surfaceContainerHighest: Color.alphaBlend(
      tint.withValues(alpha: .13),
      canvas,
    ),
  );
  return applyAppMenuTheme(
    base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      extensions: [
        ...base.extensions.values.where((e) => e is! BrandColors),
        BrandColors(colors.primary),
      ],
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: base.appBarTheme.copyWith(foregroundColor: ink),
      cardTheme: base.cardTheme.copyWith(color: surface),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: scheme.surfaceContainer,
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? null : colors.primary,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? null
                : readableOn(colors.primary),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: scheme.primaryContainer,
        labelStyle: base.chipTheme.labelStyle?.copyWith(color: ink),
        secondaryLabelStyle: base.chipTheme.secondaryLabelStyle?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        checkmarkColor: scheme.primary,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: surface,
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: surface,
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
    ),
  );
}
