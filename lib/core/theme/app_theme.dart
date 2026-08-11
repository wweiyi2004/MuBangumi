import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFFE95383);
  static const ink = Color(0xFF1D2433);
  static const canvas = Color(0xFFFAFAFC);
  static const night = Color(0xFF09090E);

  static const _fontFallback = [
    'Microsoft YaHei UI',
    'PingFang SC',
    'Noto Sans CJK SC',
  ];

  static const _textTheme = TextTheme(
    displaySmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1.2),
    headlineLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.8),
    headlineMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
    titleLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2),
    titleMedium: TextStyle(fontWeight: FontWeight.w700),
    bodyLarge: TextStyle(height: 1.55),
    bodyMedium: TextStyle(height: 1.5),
  );

  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFFFF77A2),
          secondary: const Color(0xFFA99AF7),
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
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .7)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface.withValues(alpha: .96),
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
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
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0x0F1D2433)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE8E8EF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: seed, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: seed,
        disabledColor: const Color(0xFFE9E9EF),
        checkmarkColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: const BorderSide(color: Color(0xFFE4E4EB)),
        labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 70,
        backgroundColor: Color(0xFAFFFFFF),
        indicatorColor: Color(0xFFFFE1EB),
        elevation: 0,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xFFFFE1EB),
      ),
      dividerTheme: const DividerThemeData(color: Color(0x141D2433), space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
