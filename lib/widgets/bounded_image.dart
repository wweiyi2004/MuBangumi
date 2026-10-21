import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/network/bangumi_endpoints.dart';

/// Bucket physical dimensions so small layout changes reuse the same decode.
int imageDecodeExtent(double logical, double pixelRatio) {
  final pixels = logical * pixelRatio;
  if (!pixels.isFinite || pixels <= 0) return 1024;
  return ((pixels.clamp(1, 2048) / 32).ceil() * 32).clamp(32, 2048);
}

ImageProvider boundedImageProvider(
  ImageProvider provider, {
  required double width,
  required double height,
  double pixelRatio = 1,
}) => ResizeImage(
  provider,
  width: imageDecodeExtent(width, pixelRatio),
  height: imageDecodeExtent(height, pixelRatio),
  policy: ResizeImagePolicy.fit,
  allowUpscaling: false,
);

ImageProvider boundedAvatarProvider(
  BuildContext context,
  String url, {
  required double diameter,
}) => boundedImageProvider(
  CachedNetworkImageProvider(BangumiEndpoints.imageUrl(url)),
  width: diameter,
  height: diameter,
  pixelRatio: MediaQuery.devicePixelRatioOf(context),
);

/// Uses the disk cache while decoding only within the physical display bounds.
/// `fit` preserves arbitrary community image proportions, including tall art.
class BoundedNetworkImage extends StatelessWidget {
  const BoundedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final double? width, height;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final provider = boundedImageProvider(
        CachedNetworkImageProvider(imageUrl),
        width: width ?? constraints.maxWidth,
        height: height ?? constraints.maxHeight,
        pixelRatio: dpr,
      );
      return Image(
        image: provider,
        width: width,
        height: height,
        fit: fit,
        frameBuilder: placeholder == null
            ? null
            : (context, child, frame, synchronous) =>
                  synchronous || frame != null
                  ? child
                  : placeholder!(context, imageUrl),
        errorBuilder: errorWidget == null
            ? null
            : (context, error, _) => errorWidget!(context, imageUrl, error),
      );
    },
  );
}
