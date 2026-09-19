import 'state/service_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'navigation/app_destination.dart';
import 'navigation/app_router.dart';
export 'widgets/brand_mark.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_preparation_screen.dart';
import 'state/background_controller.dart';
import 'state/session_controller.dart';
import 'state/account_access_controller.dart';
import 'state/pm_send_queue_controller.dart';
import 'state/theme_controller.dart';
import 'state/system_appearance_controller.dart';
import 'widgets/app_background.dart';
import 'widgets/app_shortcut_host.dart';
import 'widgets/login_progress.dart';
import 'widgets/update_check_host.dart';
import 'widgets/network_recovery_host.dart';

class MuBangumiApp extends ConsumerWidget {
  const MuBangumiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(accountAccessProvider);
    ref.watch(
      pmSendQueueProvider(ref.watch(pmServiceProvider)).select((_) => true),
    );
    // Collection updates do not rebuild the root; only entry state does.
    final phase = ref.watch(sessionProvider.select((state) => state.phase));
    final accountId = ref.watch(
      sessionProvider.select((state) => state.user?.id),
    );
    final preparing = ref.watch(
      sessionProvider.select((state) => state.isPreparingHome),
    );
    final themeMode = ref.watch(themeModeProvider);
    final background = ref.watch(backgroundThemeSettingsProvider);
    final system = ref.watch(systemAppearanceProvider);
    final highLight = highContrastBackgroundTheme(AppTheme.light, system);
    final highDark = highContrastBackgroundTheme(AppTheme.dark, system);
    return AppShortcutHost(
      child: MaterialApp(
        key: ValueKey('account-navigation:$accountId'),
        title: 'MuBangumi',
        debugShowCheckedModeBanner: false,
        theme: system.highContrast
            ? highLight
            : applyBackgroundTheme(AppTheme.light, background),
        darkTheme: system.highContrast
            ? highDark
            : applyBackgroundTheme(AppTheme.dark, background),
        highContrastTheme: highLight,
        highContrastDarkTheme: highDark,
        themeMode: themeMode,
        builder: (context, child) {
          return AppRouteScope(
            resolve: AppRouter.resolve,
            child: AppBackgroundHost(
              child: NetworkRecoveryHost(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
        home: UpdateCheckHost(
          allowNotices: phase == SessionPhase.signedIn,
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
