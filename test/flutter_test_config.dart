import 'dart:async';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mubangumi/core/storage/sqlite_support.dart';
import 'package:mubangumi/core/auth/auth_cleanup_marker.dart';
import 'package:mubangumi/core/auth/website_cookie_bridge.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'support/memory_community_cache.dart';

/// Unit fixtures never discover real portable databases, OS profiles, account
/// records or Downloads. Separate integration entry points keep their own
/// explicitly isolated native setup.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final root = Directory(
    '.dart_tool/unit-data/$pid-${DateTime.now().microsecondsSinceEpoch}',
  ).absolute;
  root.createSync(recursive: true);
  final paths = _UnitPaths(root);
  PathProviderPlatform.instance = paths;
  FlutterSecureStorage.setMockInitialValues({});
  AuthCleanupMarker.useMemoryForTests();
  final cache = MemoryCommunityCache();
  CommunityCache.useForTests(cache);
  PersonalDatabasePaths.isolateForTests(Directory(paths.support));
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    await databaseFactoryFfi.setDatabasesPath(paths.path('sqlite'));
  }
  setUp(() {
    PathProviderPlatform.instance = paths;
    AuthCleanupMarker.useMemoryForTests();
    cache.reset();
    CommunityCache.useForTests(cache);
    WebsiteCookieBridge.resetForTests();
    WebsiteCookieBridge.setCleanupForTests(() async {});
  });
  // Ignored synthetic files remain available for failed-suite diagnostics;
  // no recursive cleanup races with a still-running SQLite worker.
  await testMain();
}

class _UnitPaths extends PathProviderPlatform {
  _UnitPaths(this.root);
  final Directory root;
  String path(String name) {
    final directory = Directory('${root.path}/$name');
    directory.createSync(recursive: true);
    return directory.path;
  }

  String get support => path('support');
  @override
  Future<String> getApplicationSupportPath() async => support;
  @override
  Future<String> getApplicationDocumentsPath() async => path('documents');
  @override
  Future<String> getApplicationCachePath() async => path('cache');
  @override
  Future<String> getTemporaryPath() async => path('temporary');
  @override
  Future<String> getDownloadsPath() async => path('downloads');
  @override
  Future<String> getLibraryPath() async => path('library');
}
