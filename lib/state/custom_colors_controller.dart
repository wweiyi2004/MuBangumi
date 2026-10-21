import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/theme/custom_colors.dart';

class CustomColorsController extends StateNotifier<CustomColors?> {
  CustomColorsController(this.storage) : super(null) {
    ready = _restore();
  }
  final FlutterSecureStorage storage;
  static const key = 'appearance_colors_v1';
  late final Future<void> ready;
  Future<void> _tail = Future.value();
  int _revision = 0;
  Future<void> _restore() async {
    final revision = _revision;
    try {
      final raw = await storage.read(key: key);
      if (mounted && revision == _revision && raw != null) {
        state = CustomColors.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> choose(CustomColors? colors) {
    ++_revision;
    final next = _tail.then((_) async {
      if (colors == null) {
        await storage.delete(key: key);
      } else {
        await storage.write(key: key, value: jsonEncode(colors.toJson()));
      }
      if (mounted) state = colors;
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

final customColorsProvider =
    StateNotifierProvider<CustomColorsController, CustomColors?>(
      (ref) => CustomColorsController(const FlutterSecureStorage()),
    );
