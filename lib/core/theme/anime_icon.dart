import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'anime_icon_assets.dart';

/// Keeps Material icon identity/semantics while drawing our themed SVG artwork.
/// Directional and state indicators retain the meaning of their original glyph.
class AnimeIcon extends Icon {
  const AnimeIcon(
    super.icon, {
    super.key,
    super.size,
    super.color,
    super.semanticLabel,
    super.textDirection,
    super.fill,
    super.weight,
    super.grade,
    super.opticalSize,
    super.shadows,
    super.applyTextScaling,
    super.blendMode,
    super.fontWeight,
  });
  @override
  Widget build(BuildContext context) {
    final data = icon;
    if (data == null) return super.build(context);
    final asset = animeIconAssets['${data.fontFamily}:${data.codePoint}'];
    if (asset == null) return super.build(context);
    final theme = IconTheme.of(context);
    final logicalSize = size ?? theme.size ?? 24;
    final scaledSize = (applyTextScaling ?? theme.applyTextScaling ?? false)
        ? MediaQuery.textScalerOf(context).scale(logicalSize)
        : logicalSize;
    final iconColor = (color ?? theme.color ?? Colors.black).withValues(
      alpha: (color ?? theme.color ?? Colors.black).a * (theme.opacity ?? 1),
    );
    Widget picture = SvgPicture.asset(
      asset,
      width: scaledSize,
      height: scaledSize,
      colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
    if (data.matchTextDirection &&
        (textDirection ?? Directionality.of(context)) == TextDirection.rtl) {
      picture = Transform.flip(flipX: true, child: picture);
    }
    return Semantics(
      label: semanticLabel,
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox.square(dimension: scaledSize, child: picture),
      ),
    );
  }
}
