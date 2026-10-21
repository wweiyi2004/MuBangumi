import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/onboarding/watched_catalog.dart';
import '../models/bangumi_models.dart';
import 'app_providers.dart';

final watchedCatalogProvider = Provider<WatchedCatalog>((ref) {
  final api = ref.watch(bangumiApiProvider);
  return WatchedCatalog(
    fetch: ({int? year, int offset = 0, int limit = 24}) => api.browseSubjects(
      type: SubjectType.anime,
      year: year,
      sort: 'rank',
      offset: offset,
      limit: limit,
    ),
  );
});
