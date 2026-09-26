import 'package:dio/dio.dart';

extension TierPrintCancellation on CancelToken {
  void throwIfCancellationRequested() {
    final error = cancelError;
    if (error != null) throw error;
  }
}
