import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/sharing/image_export.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _Picker picker;
  setUp(() {
    picker = _Picker();
    FilePicker.platform = picker;
  });
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ImageExport.channel,
      null,
    ),
  );
  test(
    'old native baseline falls back to a user-selected file and respects cancellation',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ImageExport.channel,
        (_) async => throw MissingPluginException(),
      );
      final bytes = Uint8List.fromList([137, 80, 78, 71]);
      expect(await ImageExport.saveToGalleryOrFile(bytes, 'chart.png'), isNull);
      expect(picker.bytes, bytes);
      expect(picker.filename, 'chart.png');
      expect(picker.calls, 1);
    },
  );
  test(
    'gallery permission denial is not silently redirected to a folder',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ImageExport.channel,
        (_) async => throw PlatformException(code: 'permission_denied'),
      );
      await expectLater(
        ImageExport.saveToGalleryOrFile(Uint8List(4), 'chart.png'),
        throwsA(isA<PlatformException>()),
      );
      expect(picker.calls, 0);
    },
  );
}

class _Picker extends FilePicker {
  int calls = 0;
  Uint8List? bytes;
  String? filename;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    calls++;
    this.bytes = bytes;
    filename = fileName;
    return null;
  }
}
