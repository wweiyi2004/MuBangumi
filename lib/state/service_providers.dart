import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/community_service.dart';
import '../core/network/pm_service.dart';
import 'website_session_controller.dart';
import 'account_diagnostics_provider.dart';

/// Services are owned by a ProviderContainer, never by process-wide auth state.
final communityServiceProvider = Provider<CommunityService>((ref) {
  final service = CommunityService(
    diagnostics: ref.watch(accountDiagnosticsProvider),
    sessionStore: ref.watch(websiteSessionStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
final pmServiceProvider = Provider<PmService>((ref) {
  final service = PmService(
    diagnostics: ref.watch(accountDiagnosticsProvider),
    sessionStore: ref.watch(websiteSessionStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

// Non-consumer widgets still accept explicit test services. The default service
// is resolved from their enclosing container without creating a new scope.
CommunityService communityServiceFor(BuildContext context) =>
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(communityServiceProvider);
PmService pmServiceFor(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(pmServiceProvider);
