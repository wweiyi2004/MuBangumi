import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Refresh local views after import without recreating the login or navigator.
final localBrowsingEpochProvider = StateProvider<int>((ref) => 0);
final localImportBusyProvider = StateProvider<bool>((ref) => false);
