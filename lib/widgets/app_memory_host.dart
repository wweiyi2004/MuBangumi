import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/netaba_api.dart';
import '../state/service_providers.dart';

class AppMemoryHost extends StatefulWidget {
  const AppMemoryHost({super.key, required this.child});
  final Widget child;

  static const imageCacheBytes = 64 * 1024 * 1024;
  static const imageCacheEntries = 512;

  @override
  State<AppMemoryHost> createState() => _AppMemoryHostState();
}

class _AppMemoryHostState extends State<AppMemoryHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = AppMemoryHost.imageCacheBytes;
    cache.maximumSize = AppMemoryHost.imageCacheEntries;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didHaveMemoryPressure() {
    // Visible image streams, offline data, credentials and pending writes stay
    // owned by their existing controllers. Only disposable results are trimmed.
    PaintingBinding.instance.imageCache.clear();
    final container = ProviderScope.containerOf(context, listen: false);
    if (container.exists(communityServiceProvider)) {
      container.read(communityServiceProvider).releaseMemory();
    }
    if (container.exists(netabaApiProvider)) {
      container.read(netabaApiProvider).releaseMemory();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
