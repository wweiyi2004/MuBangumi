import 'package:flutter/foundation.dart';
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
    final raw = decodePayloadFromImageBytes(bytes);
    return raw == null ? null : decode(raw);
  }

  static String? decodePayloadFromImageBytes(Uint8List bytes) {
    try {
      if (bytes.length > 20 * 1024 * 1024) return null;
      final decoder = img.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      if (info == null ||
          info.width <= 0 ||
          info.height <= 0 ||
          info.width > 8192 ||
          info.height > 8192 ||
          info.width * info.height > 16 * 1024 * 1024) {
        return null;
      }
      final image = decoder!.decodeFrame(0);
      if (image == null) return null;
      final pixels = image
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.abgr)
          .buffer
          .asInt32List();
      final source = RGBLuminanceSource(image.width, image.height, pixels);
      final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
      return QRCodeReader().decode(bitmap).text;
    } catch (_) {
      return null;
    }
  }

  /// Off-main-thread variant for the image picker: decoding a large photo
  /// synchronously janks the UI (and can ANR on low-end devices).
  static Future<String?> decodeFromImageBytesAsync(Uint8List bytes) {
    if (bytes.length < 1024 * 1024) {
      // Small images decode fast enough; avoids isolate setup overhead.
      return Future.value(decodeFromImageBytes(bytes));
    }
    return compute(decodeFromImageBytes, bytes);
  }

  static Future<String?> decodePayloadFromImageBytesAsync(Uint8List bytes) =>
      compute(decodePayloadFromImageBytes, bytes);
}
