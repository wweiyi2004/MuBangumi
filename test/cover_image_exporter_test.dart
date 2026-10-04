import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/sharing/cover_image_exporter.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  test(
    'cover save preserves downloaded image bytes and normalizes large image URL',
    () async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jPpQAAAAASUVORK5CYII=',
      );
      RequestOptions? request;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              request = options;
              handler.resolve(
                Response(requestOptions: options, statusCode: 200, data: bytes),
              );
            },
          ),
        );
      final result = await CoverImageExporter(
        dio: dio,
      ).download('https://lain.bgm.tv/pic/cover/s/ab/42.jpg');
      expect(request?.uri.path, '/pic/cover/l/ab/42.jpg');
      expect(request?.headers.containsKey('Authorization'), false);
      expect(result.bytes, bytes);
      expect(result.extension, 'png');
    },
  );
  test(
    'HTML error pages and invalid cover URLs are not saved as images',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: utf8.encode('<html>error</html>'),
                ),
              );
            },
          ),
        );
      final exporter = CoverImageExporter(dio: dio);
      await expectLater(
        exporter.download('https://example.test/a.jpg'),
        throwsFormatException,
      );
      await expectLater(
        exporter.download('file:///secret'),
        throwsFormatException,
      );
    },
  );
  test(
    'missing Chinese title uses only an explicit Chinese name in the infobox',
    () {
      expect(
        Subject.fromJson({
          'name': '日本語',
          'name_cn': ' ',
          'infobox': [
            {
              'key': '简体中文名',
              'value': [
                {'v': '中文名称'},
              ],
            },
          ],
        }).displayName,
        '中文名称',
      );
      expect(
        Subject.fromJson({
          'name': '日本語',
          'infobox': [
            {'key': '别名', 'value': '推测的名称'},
          ],
        }).displayName,
        '日本語',
      );
    },
  );
}
