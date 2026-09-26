import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppTheme {
  static const seed = Color(0xFFE95383);
  static const ink = Color(0xFF1D2433);
  static const canvas = Color(0xFFFBFAF9);
  static const night = Color(0xFF101014);

  // Use one Windows family for both Latin and CJK glyphs. A CJK fallback
  // alone mixes the default Latin face with YaHei at different weight metrics.
  static String? get _fontFamily =>
      defaultTargetPlatform == TargetPlatform.windows
      ? 'Microsoft YaHei UI'
      : null;

  static TextStyle get _controlTextStyle => TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    fontWeight: FontWeight.w600,
  );

  static ButtonStyle get _filledButtonStyle => FilledButton.styleFrom(
    minimumSize: const Size(48, 48),
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.round),
    textStyle: _controlTextStyle,
  );

  static const _fontFallback = [
    'Microsoft YaHei UI',
    'PingFang SC',
    'Noto Sans CJK SC',
  ];

  static const _textTheme = TextTheme(
    displaySmall: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -1.2),
    headlineLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.8),
    headlineMedium: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
    titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: TextStyle(fontWeight: FontWeight.w600),
    labelLarge: TextStyle(fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontWeight: FontWeight.w400, height: 1.55),
    bodyMedium: TextStyle(fontWeight: FontWeight.w400, height: 1.5),
  );

  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFFFF77A2),
          secondary: const Color(0xFF5CC4B8),
          tertiary: const Color(0xFFF1B654),
          surface: const Color(0xFF121219),
          surfaceContainerLowest: night,
          surfaceContainerLow: const Color(0xFF16161E),
          surfaceContainer: const Color(0xFF1C1C26),
          surfaceContainerHigh: const Color(0xFF23232F),
          surfaceContainerHighest: const Color(0xFF2B2B38),
          outlineVariant: const Color(0xFF343442),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: night,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFallback,
      textTheme: _textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.medium),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _filledButtonStyle),
      chipTheme: ChipThemeData(
        labelStyle: _controlTextStyle.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: _controlTextStyle.copyWith(color: scheme.primary),
        backgroundColor: Colors.transparent,
        selectedColor: scheme.primaryContainer.withValues(alpha: .55),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.small),
        side: BorderSide.none,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface.withValues(alpha: .96),
        indicatorColor: Colors.transparent,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      pageTransitionsTheme: _pageTransitions,
    );
  }

  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: Colors.white,
        ).copyWith(
          primary: seed,
          secondary: const Color(0xFF38A89D),
          tertiary: const Color(0xFFF3A646),
          onSurface: ink,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFFBFBFD),
          surfaceContainer: const Color(0xFFF1F1F6),
          outlineVariant: const Color(0xFFE5E5EC),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFallback,
      textTheme: _textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.medium),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: const BorderSide(color: seed, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _filledButtonStyle),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: const Color(0xFFFFE8EF),
        disabledColor: const Color(0xFFE9E9EF),
        checkmarkColor: seed,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.small),
        side: BorderSide.none,
        labelStyle: _controlTextStyle.copyWith(color: ink),
        secondaryLabelStyle: _controlTextStyle.copyWith(color: seed),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 64,
        backgroundColor: Color(0xFAFFFFFF),
        indicatorColor: Colors.transparent,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: Color(0x141D2433), space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.medium),
      ),
      pageTransitionsTheme: _pageTransitions,
    );
  }

  static const _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
      TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
      TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      TargetPlatform.linux: ZoomPageTransitionsBuilder(),
    },
  );
}
