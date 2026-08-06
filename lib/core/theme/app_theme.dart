import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFFE95383);
  static const ink = Color(0xFF1D2433);
  static const canvas = Color(0xFFF7F7FA);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFFF779D),
      secondary: const Color(0xFF5ED1C5),
      tertiary: const Color(0xFFF3A646),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF12141A),
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'PingFang SC',
        'Noto Sans CJK SC',
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'PingFang SC',
        'Noto Sans CJK SC',
      ],
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        ),
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(height: 1.55),
        bodyMedium: TextStyle(height: 1.5),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFFE9E9EF)),
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
        backgroundColor: Colors.white,
        indicatorColor: Color(0xFFFFE1EB),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
