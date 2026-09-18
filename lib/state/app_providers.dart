import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/bangumi_oauth.dart';
import '../core/network/bangumi_api.dart';
import '../core/storage/snapshot_cache.dart';
import '../core/storage/token_store.dart';

final bangumiApiProvider = Provider<BangumiApi>((ref) => BangumiApi());
final bangumiOAuthProvider = Provider<BangumiOAuth>((ref) => BangumiOAuth());
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
final snapshotCacheProvider = Provider<SnapshotCache>(
  (ref) => SnapshotCache.shared,
);
