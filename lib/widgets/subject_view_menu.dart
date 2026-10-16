import 'package:flutter/material.dart';
import '../core/theme/anime_icon.dart';
import '../state/subject_view_controller.dart';

class SubjectViewMenu extends StatelessWidget {
  const SubjectViewMenu({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final SubjectView value;
  final ValueChanged<SubjectView> onChanged;
  @override
  Widget build(BuildContext context) => PopupMenuButton<SubjectView>(
    tooltip: '切换视图',
    initialValue: value,
    icon: const AnimeIcon(Icons.grid_view_rounded),
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final view in SubjectView.values)
        CheckedPopupMenuItem(
          value: view,
          checked: view == value,
          child: Text(switch (view) {
            SubjectView.adaptive => '默认视图',
            SubjectView.list => '列表视图',
            SubjectView.twoColumns => '一行 2 个',
            SubjectView.threeColumns => '一行 3 个',
          }),
        ),
    ],
  );
}
