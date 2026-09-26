import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:mubangumi/features/tier_print/tier_print_covers.dart';
import 'package:mubangumi/features/tier_print/tier_print_models.dart';

void main() {
  test(
    'covers preserve successful items, reject unrelated hosts and reuse normalized cache',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'mubangumi-tier-cover-test-',
      );
      addTearDown(() async {
        expect(
          path.isWithin(Directory.systemTemp.absolute.path, dir.absolute.path),
          true,
        );
        await dir.delete(recursive: true);
      });
      var requests = 0;
      final source = img.encodePng(img.Image(width: 20, height: 30));
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              expect(options.uri.host, 'lain.bgm.tv');
              handler.resolve(
                Response<ResponseBody>(
                  requestOptions: options,
                  statusCode: 200,
                  data: ResponseBody.fromBytes(source, 200),
                ),
              );
            },
          ),
        );
      final loader = TierPrintCovers(cache: dir, dio: dio);
      addTearDown(loader.close);
      const entries = [
        TierPrintEntry(
          id: 1,
          title: 'cover',
          date: '2025-01-01',
          coverUrl: 'https://lain.bgm.tv/fixture.png',
        ),
        TierPrintEntry(
          id: 2,
          title: 'invalid',
          date: '2025-01-01',
          coverUrl: 'https://unrelated.invalid/image.png',
        ),
      ];
      var done = 0, failed = 0;
      final first = await loader.load(
        entries,
        cancel: CancelToken(),
        progress: (d, f) {
          done = d;
          failed = f;
        },
      );
      expect(first.keys, [1]);
      expect(done, 2);
      expect(failed, 1);
      expect(requests, 1);
      final second = await loader.load(entries, cancel: CancelToken());
      expect(second.keys, [1]);
      expect(requests, 1);
      expect(img.decodeJpg(second[1]!)!.height, 30);
    },
  );
}
