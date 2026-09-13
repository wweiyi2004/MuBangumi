import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/state/system_appearance_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mubangumi/system_appearance');
  test(
    'native preference updates propagate and failed reads retain the last state',
    () async {
      var data = <String, Object>{
        'transparency': false,
        'highContrast': false,
        'batterySaver': false,
      };
      var fail = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            if (fail) throw PlatformException(code: 'read-failed');
            return data;
          });
      final controller = SystemAppearanceController(supported: true);
      await controller.reload();
      expect(controller.state.reduceEffects, isTrue);
      data = {
        'transparency': true,
        'highContrast': true,
        'background': 0xFF000000,
        'foreground': 0xFFFFFFFF,
      };
      await controller.reload();
      expect(controller.state.highContrast, isTrue);
      expect(controller.state.background, 0xFF000000);
      fail = true;
      await controller.reload();
      expect(controller.state.highContrast, isTrue);
      controller.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
