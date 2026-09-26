import 'package:flutter/material.dart';
import '../../../models/pm_models.dart';
import 'package:flutter/services.dart';
import 'pm_avatar.dart';
import '../../../widgets/social_chat_style.dart';
import '../../../core/theme/app_tokens.dart';

class PmChatBubble extends StatelessWidget {
  const PmChatBubble({super.key, required this.message, required this.avatar});

  final PmMessage message;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final self = message.isSelf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bubble = ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (constraints.maxWidth - 104).clamp(80.0, 560.0),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: self
                    ? SocialChatStyle.ownBubble(context)
                    : SocialChatStyle.paper(context),
                border: Border.all(
                  color: self
                      ? SocialChatStyle.accent(context).withValues(alpha: .05)
                      : scheme.outlineVariant.withValues(alpha: .15),
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(self ? 16 : 4),
                  topRight: Radius.circular(self ? 4 : 16),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: const Radius.circular(16),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: SelectableText(
                  message.contentText,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    fontFamilyFallback: const [
                      'Microsoft YaHei UI',
                      'Segoe UI Emoji',
                      'Apple Color Emoji',
                      'Noto Color Emoji',
                    ],
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          );
          final portrait = PmAvatar(
            url: avatar,
            name: self ? '我' : message.name,
            radius: 20,
          );
          return Row(
            mainAxisAlignment: self
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!self) ...[portrait, const SizedBox(width: 10)],
              Flexible(
                child: Column(
                  crossAxisAlignment: self
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!self && message.name.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          message.name,
                          style: TextStyle(
                            fontSize: AppText.caption,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    bubble,
                  ],
                ),
              ),
              if (self) ...[const SizedBox(width: 10), portrait],
            ],
          );
        },
      ),
    );
  }
}

class PmComposerBar extends StatelessWidget {
  const PmComposerBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 560;
      final input = TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        minLines: desktop ? 3 : 1,
        maxLines: desktop ? 6 : 4,
        textInputAction: TextInputAction.newline,
        style: const TextStyle(fontSize: 15, height: 1.5),
        decoration: InputDecoration(
          hintText: '输入回复…',
          filled: true,
          fillColor: desktop
              ? SocialChatStyle.paper(context)
              : SocialChatStyle.canvas(context),
          contentPadding: const EdgeInsets.all(12),
          border: OutlineInputBorder(
            borderRadius: AppRadius.small,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.small,
            borderSide: BorderSide.none,
          ),
        ),
      );
      final send = ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: SocialChatStyle.accent(context),
            foregroundColor: SocialChatStyle.dark(context)
                ? Colors.black
                : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.small),
          ),
          onPressed: enabled && !sending && value.text.trim().isNotEmpty
              ? onSend
              : null,
          child: sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('发送'),
        ),
      );
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
            if (enabled &&
                !sending &&
                controller.text.trim().isNotEmpty &&
                controller.value.composing.isCollapsed) {
              onSend();
            }
          },
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: SocialChatStyle.paper(context),
            border: Border(
              top: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: .4),
                width: .6,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: desktop
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        input,
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Enter 换行 · Ctrl + Enter 发送',
                                style: TextStyle(
                                  fontSize: AppText.timestamp,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            send,
                          ],
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: input),
                        const SizedBox(width: 10),
                        send,
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );
}
