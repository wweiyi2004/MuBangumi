import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../network/bangumi_endpoints.dart';
import '../network/bangumi_user_agent.dart';

class CoverImageData {
  const CoverImageData(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

/// Fetch original image bytes using a public request, without account headers.
class CoverImageExporter {
  CoverImageExporter({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              headers: {'User-Agent': muBangumiUserAgent},
            ),
          );
  final Dio _dio;

  Future<CoverImageData> download(
    String rawUrl, {
    CancelToken? cancelToken,
  }) async {
    final url = BangumiEndpoints.imageUrl(rawUrl, size: BangumiImageSize.large);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('封面地址不可用');
    }
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
      cancelToken: cancelToken,
    );
    final bytes = Uint8List.fromList(response.data ?? []);
    final extension = imageExtension(bytes);
    if (extension == null) throw const FormatException('未获取到有效封面，请重试');
    return CoverImageData(bytes, extension);
  }

  static String? imageExtension(List<int> bytes) {
    bool prefix(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((v) => v);
    if (prefix([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'png';
    if (prefix([0xff, 0xd8, 0xff])) return 'jpg';
    if (prefix([0x47, 0x49, 0x46, 0x38])) return 'gif';
    if (prefix([0x52, 0x49, 0x46, 0x46]) &&
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
    return null;
  }
}
