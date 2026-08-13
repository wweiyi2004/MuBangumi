import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

class FriendQr {
  FriendQr._();

  static const prefix = 'mubangumi:friend:v1:';

  static String encode(String username) {
    final value = username.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(username, 'username', 'empty');
    }
    return '$prefix${Uri.encodeComponent(value)}';
  }

  static String? decode(String raw) {
    final value = raw.trim();
    if (!value.startsWith(prefix)) return null;
    final encoded = value.substring(prefix.length);
    if (encoded.isEmpty) return null;
    try {
      final username = Uri.decodeComponent(encoded).trim();
      if (username.isEmpty) return null;
      return username;
    } catch (_) {
      return null;
    }
  }

  static String? decodeFromImageBytes(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    try {
      final pixels = image
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.abgr)
          .buffer
          .asInt32List();
      final source = RGBLuminanceSource(image.width, image.height, pixels);
      final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
      return decode(QRCodeReader().decode(bitmap).text);
    } catch (_) {
      return null;
    }
  }
}
