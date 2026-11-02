import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/theme/custom_colors.dart';

/// Brand artwork stays outside the code. No finder/timing/data modules are hidden.
class BrandQr extends StatelessWidget {
  const BrandQr({
    super.key,
    required this.data,
    this.size = 220,
    this.padding,
    this.backgroundColor,
    this.eyeStyle,
    this.dataModuleStyle,
  });
  final String data;
  final double size;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final QrEyeStyle? eyeStyle;
  final QrDataModuleStyle? dataModuleStyle;
  static const ink = Color(0xFF663F4A);
  @override
  Widget build(BuildContext context) => Semantics(
    label: '二维码，支持扫码识别',
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size >= 180 ? 20 : 12),
        border: Border.all(
          color: BrandColors.of(context).withValues(alpha: .5),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size >= 180 ? 20 : 12),
        child: QrImageView(
          data: data,
          size: size,
          backgroundColor: Colors.white,
          errorCorrectionLevel: size < 180
              ? QrErrorCorrectLevel.M
              : QrErrorCorrectLevel.H,
          padding: EdgeInsets.all(size >= 180 ? 18 : 12),
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: ink),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: size >= 180
                ? QrDataModuleShape.circle
                : QrDataModuleShape.square,
            color: ink,
          ),
        ),
      ),
    ),
  );
}
