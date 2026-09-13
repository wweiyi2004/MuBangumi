import 'package:flutter/material.dart';

/// Thumb-reachable actions stay visible while reading a long subject page.
class MobileSubjectActions extends StatelessWidget {
  const MobileSubjectActions({
    super.key,
    required this.collectionLabel,
    required this.onCollection,
    required this.onComment,
    this.onProgress,
    this.busy = false,
  });
  final String collectionLabel;
  final VoidCallback onCollection, onComment;
  final VoidCallback? onProgress;
  final bool busy;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            _action(
              Icons.bookmark_outline_rounded,
              collectionLabel,
              onCollection,
            ),
            if (onProgress != null)
              _action(Icons.playlist_add_check_rounded, '记进度', onProgress!),
            _action(Icons.edit_note_rounded, '写短评', onComment),
          ],
        ),
      ),
    ),
  );

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
    child: TextButton(
      onPressed: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
