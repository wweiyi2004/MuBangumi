import 'package:flutter/material.dart';
import 'app_tokens.dart';

/// Shared floating surfaces for popup actions, selection lists and menu anchors.
ThemeData applyAppMenuTheme(ThemeData theme) {
  final scheme = theme.colorScheme;
  final shape = RoundedRectangleBorder(
    borderRadius: AppRadius.large,
    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
  );
  final style = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(scheme.surface),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shape: WidgetStatePropertyAll(shape),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
    elevation: const WidgetStatePropertyAll(4),
    shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: .14)),
  );
  return theme.copyWith(
    highlightColor: scheme.primary.withValues(alpha: .10),
    popupMenuTheme: PopupMenuThemeData(
      shape: shape,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: .14),
      menuPadding: const EdgeInsets.all(8),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: .38)
              : scheme.onSurface,
        ),
      ),
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    menuTheme: MenuThemeData(style: style),
    dropdownMenuTheme: theme.dropdownMenuTheme.copyWith(menuStyle: style),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.small),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: .38)
              : scheme.onSurface,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
              ? scheme.primaryContainer.withValues(alpha: .55)
              : null,
        ),
      ),
    ),
  );
}
