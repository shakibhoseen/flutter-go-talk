import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../gen/assets.gen.dart';
import '../theme/app_colors.dart';

class Wrapper {
  Wrapper._();

  static int _bucketCacheDimension(int physicalDimension) {
    if (physicalDimension <= 64) {
      return physicalDimension;
    }

    final step = physicalDimension <= 256 ? 16 : 32;
    return ((physicalDimension + step - 1) ~/ step) * step;
  }

  static int? resolveCacheDimension(double? logicalDimension) {
    if (logicalDimension == null ||
        !logicalDimension.isFinite ||
        logicalDimension <= 0) {
      return null;
    }

    final views = WidgetsBinding.instance.platformDispatcher.views;
    final devicePixelRatio = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    final physicalDimension = (logicalDimension * devicePixelRatio).round();

    if (physicalDimension <= 0) {
      return null;
    }

    return _bucketCacheDimension(physicalDimension).clamp(1, 4096).toInt();
  }

  static double? _resolveLogicalDimensionFromConstraints(
    BoxConstraints constraints,
    double? explicitDimension,
    Axis axis,
  ) {
    if (explicitDimension != null &&
        explicitDimension.isFinite &&
        explicitDimension > 0) {
      return explicitDimension;
    }

    final maxDimension = axis == Axis.horizontal
        ? constraints.maxWidth
        : constraints.maxHeight;
    if (maxDimension.isFinite && maxDimension > 0) {
      return maxDimension;
    }

    final minDimension = axis == Axis.horizontal
        ? constraints.minWidth
        : constraints.minHeight;
    if (minDimension.isFinite && minDimension > 0) {
      return minDimension;
    }

    return explicitDimension;
  }

  static Widget _buildCachedNetworkImage({
    required String imageUrl,
    double? width,
    double? height,
    double? radiusCircular,
    required BoxFit fit,
    required bool isLogoAsErrorIcon,
    IconData? errorIcon,
    ValueChanged<Object>? onError,
  }) {
    final cacheWidth = resolveCacheDimension(width);
    final cacheHeight = resolveCacheDimension(height);
    return CachedNetworkImage(
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      maxWidthDiskCache: cacheWidth,
      maxHeightDiskCache: cacheHeight,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      filterQuality: FilterQuality.low,
      placeholder: (_, _) => ClipRRect(
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(radiusCircular ?? 0),
        child: Assets.images.packlyLoadingImageIcon.image(
          height: height,
          width: width,
          fit: BoxFit.cover,
        ),
      ),
      imageUrl: imageUrl,
      errorListener: onError,
      errorWidget: (_, _, _) => errorIcon == null
          ? setSVGImage(
              imagePath: isLogoAsErrorIcon
                  ? Assets.icons.packlyImge
                  : Assets.icons.noImage,
              width: width,
              height: height,
              fit: fit,
            )
          : Icon(errorIcon),
    );
  }

  /// Renders whatever [path] turns out to be — asset or URL, vector or raster.
  ///
  /// Use this whenever the path comes from *data* rather than being written in
  /// the widget. A repository (and later an API) decides its own formats, so the
  /// call site cannot know which loader is right, and picking the wrong one
  /// fails in the worst possible way: [SvgPicture] handed a PNG renders nothing,
  /// silently, with a clean analyzer. That has already cost this codebase a
  /// round of blank checkout thumbnails.
  ///
  /// Where the path *is* a literal in the widget, keep calling the specific
  /// helper — the format is known there, and being explicit is clearer.
  static Widget setImage({
    required String path,
    double? height,
    double? width,
    BoxFit fit = BoxFit.contain,
    ColorFilter? colorFilter,
    AlignmentGeometry alignment = Alignment.center,
  }) {
    final isSvg = path.toLowerCase().endsWith('.svg');
    final isRemote = path.startsWith('http');

    if (isRemote) {
      return isSvg
          ? setSVGNetworkImage(
              imageUrl: path,
              height: height,
              width: width,
              fit: fit,
              colorFilter: colorFilter,
            )
          : setCachedNetworkImage(
              imageUrl: path,
              height: height,
              width: width,
              fit: fit,
            );
    }

    if (isSvg) {
      return setSVGImage(
        imagePath: path,
        height: height,
        width: width,
        fit: fit,
        colorFilter: colorFilter,
        alignment: alignment,
      );
    }

    return Image.asset(
      path,
      height: height,
      width: width,
      fit: fit,
      alignment: alignment,
      // A missing or mistyped asset would otherwise throw mid-build and take
      // the whole screen with it; an empty box is recoverable.
      errorBuilder: (context, error, stackTrace) =>
          SizedBox(width: width, height: height),
    );
  }

  /// For SVG image
  static Widget setSVGImage({
    required String imagePath,
    double? height,
    double? width,
    ColorFilter? colorFilter,
    Size? size,
    BoxFit fit = BoxFit.cover,
    AlignmentGeometry alignment = Alignment.center,
  }) {
    return SvgPicture.asset(
      imagePath,
      height: size?.height ?? height,
      width: size?.width ?? width,
      colorFilter: colorFilter,
      fit: fit,
      alignment: alignment,
      placeholderBuilder: (context) => SizedBox(
        width: size?.width ?? width,
        height: size?.height ?? height,
        child: const Center(),
      ),
      // Handle SVG parsing errors gracefully
      excludeFromSemantics: true,
    );
  }

  //network svg
  static Widget setSVGNetworkImage({
    required String imageUrl,
    double? height,
    double? width,
    ColorFilter? colorFilter,
    Size? size,
    BoxFit fit = BoxFit.cover,
  }) {
    return SvgPicture.network(
      imageUrl,
      height: size?.height ?? height,
      width: size?.width ?? width,
      colorFilter: colorFilter,
      fit: fit,
    );
  }

  /// For Cached Network image
  static Widget setCachedNetworkImage({
    required String imageUrl,
    double? width,
    double? height,
    double? radiusCircular,
    BoxFit fit = BoxFit.cover,
    Color placeholderColor = Colors.grey,
    IconData? errorIcon,
    bool isLogoAsErrorIcon = false,
    bool resolveFromConstraints = true,
    ValueChanged<Object>? onError,
  }) {
    if (imageUrl.isEmpty) {
      return setSVGImage(
        imagePath: isLogoAsErrorIcon
            ? Assets.icons.packlyImge
            : Assets.icons.noImage,
        width: width,
        height: height,
        fit: fit,
      );
    }
    if (!resolveFromConstraints || (width != null && height != null)) {
      return _buildCachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        radiusCircular: radiusCircular,
        fit: fit,
        isLogoAsErrorIcon: isLogoAsErrorIcon,
        errorIcon: errorIcon,
        onError: onError,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth = _resolveLogicalDimensionFromConstraints(
          constraints,
          width,
          Axis.horizontal,
        );
        final resolvedHeight = _resolveLogicalDimensionFromConstraints(
          constraints,
          height,
          Axis.vertical,
        );
        return _buildCachedNetworkImage(
          imageUrl: imageUrl,
          width: resolvedWidth,
          height: resolvedHeight,
          radiusCircular: radiusCircular,
          fit: fit,
          isLogoAsErrorIcon: isLogoAsErrorIcon,
          errorIcon: errorIcon,
          onError: onError,
        );
      },
    );
  }

  static ImageProvider<Object>? cachedImageProvider({
    required String imageUrl,
    double? width,
    double? height,
    ValueChanged<Object>? onError,
  }) {
    if (imageUrl.isEmpty) {
      return null;
    }

    return CachedNetworkImageProvider(
      imageUrl,
      maxWidth: resolveCacheDimension(width),
      maxHeight: resolveCacheDimension(height),
      errorListener: onError,
    );
  }

  /// For Shimmer effect
  static Widget setShimmerEffect({
    double? width,
    double? height,
    double? radiusCircular,
    Color placeholderColor = Colors.grey,
  }) {
    return Shimmer.fromColors(
      baseColor: placeholderColor,
      highlightColor: AppColors.foundationWhite,
      child: ClipRRect(
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(radiusCircular ?? 0),
        child: Container(
          width: width ?? 17.w,
          height: height ?? 4.h,
          color: placeholderColor,
        ),
      ),
    );
  }

  /// For URL launcher
  static Future<void> launchRelevantApp({required Uri url}) async {
    if (!await launchUrl(
      url,
      mode: Platform.isIOS
          ? LaunchMode.externalApplication
          : LaunchMode.externalNonBrowserApplication,
    )) {
      throw Exception('Could not launch $url');
    }
  }

  /// For Rating bar
  static Widget buildRatingBar({
    required Function(double) onRatingUpdate,
    double initialRating = 0,
    double minRating = 0,
    int itemCount = 5,
    bool allowHalfRating = false,
    Axis direction = Axis.horizontal,
    required double iconSize,
    bool ignoreGestures = false,
    bool isGlow = false,
    Color? unratedColor,
    required String ratingIconPath,
  }) {
    return RatingBar.builder(
      glow: isGlow,
      unratedColor: unratedColor ?? AppColors.neutralColor.shade200,
      ignoreGestures: ignoreGestures,
      itemSize: iconSize,
      initialRating: initialRating,
      minRating: minRating,
      direction: direction,
      allowHalfRating: allowHalfRating,
      itemCount: itemCount,
      itemBuilder: (context, _) => setSVGImage(imagePath: ratingIconPath),
      onRatingUpdate: onRatingUpdate,
    );
  }
}
