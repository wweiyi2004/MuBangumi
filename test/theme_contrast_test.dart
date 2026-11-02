import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/core/theme/app_tokens.dart';
import 'package:mubangumi/core/theme/custom_colors.dart';
import 'package:mubangumi/widgets/social_chat_style.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void main() {
  test('light text actions meet contrast without changing brand primary', () {
    final theme = AppTheme.light;
    final scheme = theme.colorScheme;
    final textButton = theme.textButtonTheme.style!;
    final outlinedButton = theme.outlinedButtonTheme.style!;
    final foregrounds = [
      textButton.foregroundColor!.resolve({})!,
      outlinedButton.foregroundColor!.resolve({})!,
      theme.chipTheme.secondaryLabelStyle!.color!,
      theme.chipTheme.checkmarkColor!,
      theme.tabBarTheme.labelColor!,
    ];

    for (final foreground in foregrounds) {
      expect(foreground, AppPalette.roseInk);
      for (final background in [
        scheme.surface,
        scheme.surfaceContainer,
        theme.scaffoldBackgroundColor,
        theme.chipTheme.selectedColor!,
      ]) {
        expect(
          _contrast(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: 'Insufficient contrast for $foreground on $background',
        );
      }
    }
    expect(scheme.primary, AppPalette.bangumiPink);
    expect(AppTheme.dark.colorScheme.primary, AppPalette.bangumiPink);
  });

  testWidgets('social selection uses readable default and custom accents', (
    tester,
  ) async {
    late Color defaultAccent, customAccent, darkAccent;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            defaultAccent = SocialChatStyle.accent(context);
            final custom = applyCustomColors(
              AppTheme.light,
              const CustomColors(primary: Colors.blue),
            );
            customAccent = custom.textButtonTheme.style!.foregroundColor!
                .resolve({})!;
            expect(customAccent, custom.colorScheme.primary);
            expect(custom.tabBarTheme.labelColor, custom.colorScheme.primary);
            return Theme(
              data: AppTheme.dark,
              child: Builder(
                builder: (context) {
                  darkAccent = SocialChatStyle.accent(context);
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );

    expect(defaultAccent, AppPalette.roseInk);
    expect(
      _contrast(defaultAccent, AppTheme.light.colorScheme.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(darkAccent, AppPalette.bangumiPink);
  });
}
