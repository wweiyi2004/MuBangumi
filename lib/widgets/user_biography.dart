import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/sharing/share_content.dart' show plainShareText;
import '../state/service_providers.dart';
import 'biography_dialog.dart';

final userBiographyProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, username) {
    final value = Completer<String>();
    var disposed = false;
    final timer = Timer(const Duration(seconds: 12), () {
      if (!value.isCompleted) value.completeError(TimeoutException('自我介绍读取超时'));
    });
    ref.onDispose(() {
      disposed = true;
      timer.cancel();
    });
    ref
        .watch(communityServiceProvider)
        .loadUserBiography(username)
        .then<void>(
          (bio) {
            timer.cancel();
            if (!disposed && !value.isCompleted) value.complete(bio);
          },
          onError: (Object error, StackTrace stack) {
            timer.cancel();
            if (!disposed && !value.isCompleted) {
              value.completeError(error, stack);
            }
          },
        );
    return value.future;
  },
);

class UserBiography extends ConsumerWidget {
  const UserBiography({super.key, required this.username});
  final String username;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(userBiographyProvider(username));
    if (value.isLoading || value.valueOrNull?.trim().isEmpty == true) {
      return const SizedBox.shrink();
    }
    if (value.hasError) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => ref.invalidate(userBiographyProvider(username)),
          child: const Text('重试读取自我介绍'),
        ),
      );
    }
    final bio = value.valueOrNull ?? '';
    if (bio.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('自我介绍', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            plainShareText(
              bio.replaceAll(
                RegExp(
                  r'\[(?:mask|spoiler)[^\]]*\].*?\[/(?:mask|spoiler)\]',
                  caseSensitive: false,
                  dotAll: true,
                ),
                '[折叠内容]',
              ),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => BiographyDialog(source: bio, username: username),
            ),
            child: const Text('查看完整介绍'),
          ),
        ],
      ),
    );
  }
}
