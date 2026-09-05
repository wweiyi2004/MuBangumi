import 'package:flutter/material.dart';

/// Progress describes completed stages, not a guessed network percentage.
class LoginProgress extends StatelessWidget {
  const LoginProgress({super.key, required this.stage, required this.detail});

  final int stage;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const labels = ['授权', '验证账号', '准备首页'];
    return Semantics(
      liveRegion: true,
      label: '登录步骤 ${stage + 1}/3，${labels[stage]}。$detail',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var index = 0; index < labels.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: index < stage
                                ? 1
                                : index == stage
                                ? null
                                : 0,
                            minHeight: 4,
                            color: colors.primary,
                            backgroundColor: colors.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${index + 1} ${labels[index]}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: index <= stage
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animate only the incoming screen so signed-out users never see an old
/// account retained by an outgoing AnimatedSwitcher child.
class LoginEntrance extends StatelessWidget {
  const LoginEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
