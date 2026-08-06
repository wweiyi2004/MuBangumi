import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'state/session_controller.dart';

class MuBangumiApp extends ConsumerWidget {
  const MuBangumiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only rebuild the root shell when auth phase changes.
    final phase = ref.watch(sessionProvider.select((state) => state.phase));
    return MaterialApp(
      title: 'MuBangumi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: switch (phase) {
        SessionPhase.booting => const _LaunchScreen(),
        SessionPhase.signedOut => const AuthScreen(),
        SessionPhase.signedIn => const HomeShell(),
      },
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandMark(size: 76),
          const SizedBox(height: 22),
          Text('MuBangumi', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 28),
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ],
      ),
    ),
  );
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
