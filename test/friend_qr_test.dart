import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mubangumi/core/social/friend_qr.dart';
import 'package:zxing2/qrcode.dart';

void main() {
  test('encodes a client-only friend payload', () {
    expect(FriendQr.encode('wweiyi'), 'mubangumi:friend:v1:wweiyi');
  });

  test('encodes usernames that need escaping', () {
    expect(
      FriendQr.encode('user name'),
      'mubangumi:friend:v1:user%20name',
    );
  });

  test('decodes a valid payload', () {
    expect(FriendQr.decode('mubangumi:friend:v1:wweiyi'), 'wweiyi');
    expect(FriendQr.decode('  mubangumi:friend:v1:user%20name  '), 'user name');
  });

  test('decodes a generated QR image', () {
    final payload = FriendQr.encode('wweiyi');
    final qr = Encoder.encode(payload, ErrorCorrectionLevel.m);
    final matrix = qr.matrix!;
    const scale = 8;
    final image = img.Image(
      width: matrix.width * scale,
      height: matrix.height * scale,
    );
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    for (var x = 0; x < matrix.width; x++) {
      for (var y = 0; y < matrix.height; y++) {
        if (matrix.get(x, y) == 1) {
          img.fillRect(
            image,
            x1: x * scale,
            y1: y * scale,
            x2: x * scale + scale - 1,
            y2: y * scale + scale - 1,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }
    final bytes = Uint8List.fromList(img.encodePng(image));
    expect(FriendQr.decodeFromImageBytes(bytes), 'wweiyi');
  });

  test('rejects empty, foreign, or malformed payloads', () {
    expect(FriendQr.decode(''), isNull);
    expect(FriendQr.decode('https://bgm.tv/user/wweiyi'), isNull);
    expect(FriendQr.decode('mubangumi://oauth/complete'), isNull);
    expect(FriendQr.decode('mubangumi:friend:v1:'), isNull);
    expect(FriendQr.decode('mubangumi:friend:v2:wweiyi'), isNull);
  });
}
