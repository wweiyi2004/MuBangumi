import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/state/background_controller.dart';

void main() {
  test('serializes and clamps background settings', () {
    final settings = AppBackgroundSettings.fromJson({
      'enabled': true,
      'imagePath': r'C:\tmp\wall.jpg',
      'blur': 99,
      'dim': -1,
      'glass': 2,
    });
    expect(settings.enabled, isTrue);
    expect(settings.imagePath, r'C:\tmp\wall.jpg');
    expect(settings.blur, 40);
    expect(settings.dim, 0);
    expect(settings.glass, 0.8);

    final roundTrip = AppBackgroundSettings.fromJson(settings.toJson());
    expect(roundTrip.blur, settings.blur);
    expect(roundTrip.dim, settings.dim);
    expect(roundTrip.glass, settings.glass);
  });

  test('isActive requires enabled and existing image path flag', () {
    const empty = AppBackgroundSettings(enabled: true);
    expect(empty.isActive, isFalse);
    expect(empty.hasImage, isFalse);
  });
}
