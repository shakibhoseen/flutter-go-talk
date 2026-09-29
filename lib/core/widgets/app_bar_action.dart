import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/text_font_style.dart';

/// A trailing button for [CustomMaterialComponent.appBar].
///
/// Every shop_v2 header repeats the same shape — a 36pt tap target holding a
/// ~20pt glyph, optionally with a count badge — so it lives here instead of
/// being re-declared in each feature's own app bar.
///
/// Pass either [iconPath] (an SVG asset) or [icon] (a Material glyph).
class AppBarAction extends StatelessWidget {
  const AppBarAction({
    super.key,
    this.iconPath,
    this.icon,
    this.glyphSize,
    this.badgeCount = 0,
    this.mirrored = false,
    this.tint,
    this.onTap,
  }) : assert(
         iconPath != null || icon != null,
         'AppBarAction needs either iconPath or icon',
       );
  final String? iconPath;
  final IconData? icon;

  /// Glyph size inside the 36pt box. Defaults to the design's 20pt.
  final double? glyphSize;

  /// Zero hides the badge.
  final int badgeCount;

  /// Some headers use a horizontally mirrored copy of the search glyph.
  final bool mirrored;

  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = glyphSize ?? AppDimens.width20;

    Widget glyph = iconPath != null
        ? SvgPicture.asset(
            iconPath!,
            width: size,
            height: size,
            colorFilter: tint == null
                ? null
                : ColorFilter.mode(tint!, BlendMode.srcIn),
          )
        : Icon(
            icon,
            size: size,
            color: tint ?? AppColors.neutralColor.shade900,
          );

    if (mirrored) glyph = Transform.flip(flipX: true, child: glyph);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: AppDimens.width36,
        height: AppDimens.height36,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(child: glyph),
            if (badgeCount > 0)
              Positioned(
                right: AppDimens.width2,
                top: AppDimens.height2,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: AppDimens.width2),
                  constraints: BoxConstraints(
                    minWidth: AppDimens.width14,
                    minHeight: AppDimens.height14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.errorColor,
                    borderRadius: BorderRadius.circular(AppDimens.radius8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$badgeCount',
                    textAlign: TextAlign.center,
                    style: TextFontStyle.semi12sp.copyWith(
                      fontSize: AppDimens.spMin8,
                      color: AppColors.foundationWhite,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
