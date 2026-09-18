import 'package:flutter/material.dart';
import '../../../models/schedule_models.dart';

Future<void> showScheduleSeasonDialog(
  BuildContext context, {
  required SeasonKey current,
  required Future<void> Function(SeasonKey) onCreate,
}) async {
  var year = current.year;
  var quarter = current.quarter;
  final created = await showDialog<SeasonKey>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('新建 / 打开季度表'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: year,
                        decoration: const InputDecoration(labelText: '年份'),
                        items: [
                          for (var y = DateTime.now().year + 2; y >= 2000; y--)
                            DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                        onChanged: (value) {
                          if (value != null) setLocal(() => year = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: quarter,
                        decoration: const InputDecoration(labelText: '季度'),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('冬季（1月）')),
                          DropdownMenuItem(value: 1, child: Text('春季（4月）')),
                          DropdownMenuItem(value: 2, child: Text('夏季（7月）')),
                          DropdownMenuItem(value: 3, child: Text('秋季（10月）')),
                        ],
                        onChanged: (value) {
                          if (value != null) setLocal(() => quarter = value);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  SeasonKey(year: year, quarter: quarter),
                ),
                child: const Text('打开'),
              ),
            ],
          );
        },
      );
    },
  );
  if (!context.mounted || created == null) return;
  await onCreate(created);
}
