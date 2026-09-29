// dart format width=80

/// GENERATED CODE - DO NOT MODIFY BY HAND
/// *****************************************************
///  FlutterGen
/// *****************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: deprecated_member_use,directives_ordering,implicit_dynamic_list_literal,unnecessary_import

import 'package:flutter/widgets.dart';

class $AssetsAnimationJsonGen {
  const $AssetsAnimationJsonGen();

  /// File path: assets/animation_json/packly_loading_1.json
  String get packlyLoading1 => 'assets/animation_json/packly_loading_1.json';

  /// File path: assets/animation_json/rider_arrived.json
  String get riderArrived => 'assets/animation_json/rider_arrived.json';

  /// File path: assets/animation_json/rider_going.json
  String get riderGoing => 'assets/animation_json/rider_going.json';

  /// List of all assets
  List<String> get values => [packlyLoading1, riderArrived, riderGoing];
}

class $AssetsIconsGen {
  const $AssetsIconsGen();

  /// File path: assets/icons/arrow_left_icon.svg
  String get arrowLeftIcon => 'assets/icons/arrow_left_icon.svg';

  /// File path: assets/icons/arrow_left_without_line_icon.svg
  String get arrowLeftWithoutLineIcon =>
      'assets/icons/arrow_left_without_line_icon.svg';

  /// File path: assets/icons/eye_off_real_icon.svg
  String get eyeOffRealIcon => 'assets/icons/eye_off_real_icon.svg';

  /// File path: assets/icons/no_image.svg
  String get noImage => 'assets/icons/no_image.svg';

  /// File path: assets/icons/packly_imge.svg
  String get packlyImge => 'assets/icons/packly_imge.svg';

  /// File path: assets/icons/visibility_on_icon.svg
  String get visibilityOnIcon => 'assets/icons/visibility_on_icon.svg';

  /// List of all assets
  List<String> get values => [
    arrowLeftIcon,
    arrowLeftWithoutLineIcon,
    eyeOffRealIcon,
    noImage,
    packlyImge,
    visibilityOnIcon,
  ];
}

class $AssetsImagesGen {
  const $AssetsImagesGen();

  /// File path: assets/images/packly_loading_image_icon.png
  AssetGenImage get packlyLoadingImageIcon =>
      const AssetGenImage('assets/images/packly_loading_image_icon.png');

  /// List of all assets
  List<AssetGenImage> get values => [packlyLoadingImageIcon];
}

abstract final class Assets {
  static const $AssetsAnimationJsonGen animationJson =
      $AssetsAnimationJsonGen();
  static const AssetGenImage bglove = AssetGenImage('assets/bglove.jpg');
  static const AssetGenImage darkBg = AssetGenImage('assets/dark_bg.png');
  static const AssetGenImage defaults = AssetGenImage('assets/defaults.jpg');
  static const $AssetsIconsGen icons = $AssetsIconsGen();
  static const $AssetsImagesGen images = $AssetsImagesGen();
  static const AssetGenImage lightBg = AssetGenImage('assets/light_bg.png');

  /// List of all assets
  static List<AssetGenImage> get values => [bglove, darkBg, defaults, lightBg];
}

class AssetGenImage {
  const AssetGenImage(
    this._assetName, {
    this.size,
    this.flavors = const {},
    this.animation,
  });

  final String _assetName;

  final Size? size;
  final Set<String> flavors;
  final AssetGenImageAnimation? animation;

  Image image({
    Key? key,
    AssetBundle? bundle,
    ImageFrameBuilder? frameBuilder,
    ImageErrorWidgetBuilder? errorBuilder,
    String? semanticLabel,
    bool excludeFromSemantics = false,
    double? scale,
    double? width,
    double? height,
    Color? color,
    Animation<double>? opacity,
    BlendMode? colorBlendMode,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    ImageRepeat repeat = ImageRepeat.noRepeat,
    Rect? centerSlice,
    bool matchTextDirection = false,
    bool gaplessPlayback = true,
    bool isAntiAlias = false,
    String? package,
    FilterQuality filterQuality = FilterQuality.medium,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return Image.asset(
      _assetName,
      key: key,
      bundle: bundle,
      frameBuilder: frameBuilder,
      errorBuilder: errorBuilder,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      scale: scale,
      width: width,
      height: height,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      gaplessPlayback: gaplessPlayback,
      isAntiAlias: isAntiAlias,
      package: package,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }

  ImageProvider provider({AssetBundle? bundle, String? package}) {
    return AssetImage(_assetName, bundle: bundle, package: package);
  }

  String get path => _assetName;

  String get keyName => _assetName;
}

class AssetGenImageAnimation {
  const AssetGenImageAnimation({
    required this.isAnimation,
    required this.duration,
    required this.frames,
  });

  final bool isAnimation;
  final Duration duration;
  final int frames;
}
