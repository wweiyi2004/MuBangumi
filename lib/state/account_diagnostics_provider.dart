import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/diagnostics/account_diagnostics.dart';

final accountDiagnosticsProvider = Provider<AccountDiagnostics>(
  (ref) => AccountDiagnostics(),
);
