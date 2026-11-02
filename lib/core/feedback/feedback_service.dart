import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'feedback_submission.dart';

typedef FeedbackDeviceInfoLoader = Future<FeedbackDeviceInfo> Function();

class FeedbackException implements Exception {
  const FeedbackException(this.message);
  final String message;

  @override
  String toString() => message;
}

class FeedbackService {
  FeedbackService({
    Dio? dio,
    String endpoint = defaultEndpoint,
    FeedbackDeviceInfoLoader? deviceInfoLoader,
  }) : _dio = dio ?? Dio(_options),
       _endpoint = endpoint.trim(),
       _deviceInfoLoader = deviceInfoLoader ?? _readDeviceInfo;

  static const defaultEndpoint = String.fromEnvironment(
    'MUBANGUMI_FEEDBACK_URL',
  );
  static final _options = BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: const {'Accept': 'application/json'},
  );

  final Dio _dio;
  final String _endpoint;
  final FeedbackDeviceInfoLoader _deviceInfoLoader;

  static Future<FeedbackDeviceInfo> _readDeviceInfo() async {
    final info = await PackageInfo.fromPlatform();
    return FeedbackDeviceInfo(
      appVersion: info.version,
      buildNumber: info.buildNumber,
      platform: Platform.operatingSystem,
    );
  }

  Future<void> submit({
    required FeedbackCategory category,
    required String message,
    String email = '',
    bool includeDeviceInfo = true,
  }) async {
    final trimmedMessage = message.trim();
    final trimmedEmail = email.trim();
    if (trimmedMessage.isEmpty || trimmedMessage.length > 4000) {
      throw const FeedbackException('请填写 1–4000 字反馈内容');
    }
    if (trimmedEmail.isNotEmpty && !_validEmail(trimmedEmail)) {
      throw const FeedbackException('请输入有效的联系邮箱');
    }
    final uri = Uri.tryParse(_endpoint);
    final isLocal = uri?.host == 'localhost' || uri?.host == '127.0.0.1';
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && isLocal))) {
      throw const FeedbackException('反馈服务尚未配置，请稍后再试');
    }

    var deviceInfo = const FeedbackDeviceInfo(
      appVersion: '',
      buildNumber: '',
      platform: '',
    );
    if (includeDeviceInfo) {
      try {
        deviceInfo = await _deviceInfoLoader();
      } catch (_) {}
    }
    final submission = FeedbackSubmission(
      category: category,
      message: trimmedMessage,
      email: trimmedEmail,
      includeDeviceInfo: includeDeviceInfo,
      deviceInfo: deviceInfo,
    );

    try {
      final response = await _dio.post<dynamic>(
        _endpoint,
        data: submission.toJson(),
      );
      final data = response.data;
      if (data is! Map || data['ok'] != true) {
        throw const FeedbackException('提交未确认，请稍后重试');
      }
    } on DioException catch (error) {
      throw FeedbackException(_errorMessage(error));
    }
  }

  static bool _validEmail(String email) =>
      email.length <= 254 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

  static String _errorMessage(DioException error) =>
      switch (error.response?.statusCode) {
        400 => '提交内容未通过校验，请检查后重试',
        413 => '反馈内容过长，请适当精简后重试',
        429 => '提交较频繁，请稍后再试',
        _ => '提交失败，请检查网络后稍后重试',
      };

  void dispose() => _dio.close();
}
