import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/shortcuts/shared_bangumi_link.dart';

class SharedLinkRequest {
  SharedLinkRequest(String text) : links = SharedBangumiLink.fromText(text);
  final List<SharedBangumiLink> links;
}

class PendingSharedLinks extends StateNotifier<List<SharedLinkRequest>> {
  PendingSharedLinks() : super(const []);
  void offer(String text) =>
      state = [...state.take(7), SharedLinkRequest(text)];
  SharedLinkRequest? take() {
    if (state.isEmpty) return null;
    final first = state.first;
    state = state.sublist(1);
    return first;
  }
}

final pendingSharedLinksProvider =
    StateNotifierProvider<PendingSharedLinks, List<SharedLinkRequest>>(
      (ref) => PendingSharedLinks(),
    );
