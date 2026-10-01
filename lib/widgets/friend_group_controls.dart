import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/friend_groups_controller.dart';
import '../state/session_controller.dart';
import '../core/theme/anime_icon.dart';

Future<void> showFriendGroupManager(BuildContext context, int ownerId) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => FriendGroupManager(ownerId: ownerId),
    );

class FriendGroupManager extends ConsumerWidget {
  const FriendGroupManager({super.key, required this.ownerId});
  final int ownerId;
  bool _current(WidgetRef ref) => ref.read(sessionProvider).user?.id == ownerId;
  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String? id,
    String name,
  ) async {
    final field = TextEditingController(text: name);
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(id == null ? '新建本地分组' : '重命名分组'),
          content: TextField(
            controller: field,
            maxLength: 24,
            autofocus: true,
            decoration: const InputDecoration(labelText: '分组名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, field.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (value == null || !context.mounted || !_current(ref)) return;
      await ref
          .read(friendGroupsProvider(ownerId).notifier)
          .edit((g) => g.rename(id, value));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      field.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendGroupsProvider(ownerId));
    final current =
        ref.watch(sessionProvider.select((s) => s.user?.id)) == ownerId;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('好友分组', style: Theme.of(context).textTheme.titleLarge),
            const Text('分组只保存在本地，不会修改官网好友关系。'),
            if (!current)
              const Text('账号已变化，请重新打开')
            else if (state.loading)
              const LinearProgressIndicator()
            else if (state.error != null)
              TextButton(
                onPressed: () =>
                    ref.read(friendGroupsProvider(ownerId).notifier).retry(),
                child: Text(state.error!),
              )
            else ...[
              for (final group in state.groups.names.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(group.value),
                  subtitle: Text(
                    '${state.groups.members.values.where((v) => v == group.key).length} 位好友',
                  ),
                  onTap: () => _rename(context, ref, group.key, group.value),
                  trailing: IconButton(
                    tooltip: '删除分组',
                    icon: const AnimeIcon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('删除本地分组？'),
                          content: Text('“${group.value}”中的好友将回到未分组。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('删除分组'),
                            ),
                          ],
                        ),
                      );
                      if (yes != true || !context.mounted || !_current(ref)) {
                        return;
                      }
                      try {
                        await ref
                            .read(friendGroupsProvider(ownerId).notifier)
                            .edit((g) => g.remove(group.key));
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$error')));
                        }
                      }
                    },
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => _rename(context, ref, null, ''),
                icon: const AnimeIcon(Icons.add_rounded),
                label: const Text('新建分组'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
