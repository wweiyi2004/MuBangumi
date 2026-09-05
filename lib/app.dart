import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_preparation_screen.dart';
import 'state/background_controller.dart';
import 'state/session_controller.dart';
import 'state/theme_controller.dart';
import 'widgets/app_background.dart';
import 'widgets/app_shortcut_host.dart';
import 'widgets/login_progress.dart';
import 'widgets/update_check_host.dart';

class MuBangumiApp extends ConsumerWidget {
  const MuBangumiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Collection updates do not rebuild the root; only entry state does.
    final phase = ref.watch(sessionProvider.select((state) => state.phase));
    final preparing = ref.watch(
      sessionProvider.select((state) => state.isPreparingHome),
    );
    final themeMode = ref.watch(themeModeProvider);
    final background = ref.watch(backgroundSettingsProvider);
    return AppShortcutHost(
      child: MaterialApp(
        title: 'MuBangumi',
        debugShowCheckedModeBanner: false,
        theme: applyBackgroundTheme(AppTheme.light, background),
        darkTheme: applyBackgroundTheme(AppTheme.dark, background),
        themeMode: themeMode,
        builder: (context, child) {
          return AppBackgroundHost(child: child ?? const SizedBox.shrink());
        },
        home: UpdateCheckHost(
          child: switch (phase) {
            SessionPhase.booting => const LoginPreparationScreen(
              key: ValueKey('restore-login'),
            ),
            SessionPhase.signedOut => const AuthScreen(),
            SessionPhase.signedIn =>
              preparing
                  ? LoginPreparationScreen(
                      key: const ValueKey('prepare-home'),
                      nickname: ref.read(sessionProvider).user?.nickname,
                      onEnter: ref.read(sessionProvider.notifier).enterHomeNow,
                    )
                  : const LoginEntrance(
                      key: ValueKey('home-entrance'),
                      child: HomeShell(),
                    ),
          },
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF779D), Color(0xFFE7447A)],
      ),
      borderRadius: BorderRadius.circular(size * .3),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33E95383),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Icon(
      Icons.play_arrow_rounded,
      color: Colors.white,
      size: size * .64,
    ),
  );
}
