import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';

import '../../gen/assets.gen.dart';
import '../helper/ui_helpers.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/text_font_style.dart';

enum AppBarType { typeLine, typeWithoutLine }

class CustomMaterialComponent {
  /// hold appbar and other material component
  static AppBar appBar({
    required BuildContext context,
    String? title,
    Widget? titleWidget,
    TextStyle? titleStyle,
    PreferredSizeWidget? bottom,
    bool transparentType = false,
    AppBarType appBarType = AppBarType.typeLine,
    bool isLeading = true,
    centerTitle = false,
    double scrolledUnderElevation = 2,
    double elevation = 0,
    List<Widget>? action,

    /// Fills the bar. Null keeps the theme's surface, which is what every
    /// screen but the flash sale's coloured ones wants.
    Color? backgroundColor,

    /// Tints the back arrow and the default title. Only pass this alongside
    /// [backgroundColor]: on the standard white bar the arrow is
    /// [AppColors.foundationBlack] by design team's call, and a screen wanting
    /// something else there should be raised with them, not overridden here.
    /// A *coloured* bar is different — black can be unreadable on it.
    Color? foregroundColor,

    /// Status-bar icon style. A dark [backgroundColor] needs light icons.
    SystemUiOverlayStyle? systemOverlayStyle,
  }) {
    // Material's defaults put the arrow 12px from the edge and the title a
    // further 28px away (a 56px leading slot centring a 32px tap target, plus
    // the 16px default titleSpacing). The design wants 16px in from the edge
    // and an 8px gap, so the slot is sized to the arrow and titleSpacing is
    // folded into it. Without a leading there is nothing to align to, so the
    // Material default stands.
    final leadingLeftInset = AppDimens.width16 - 6;
    final leadingSlotWidth =
        AppDimens.width16 + AppDimens.spMin20 + AppDimens.width8;

    return AppBar(
      actions: action,
      automaticallyImplyLeading: false,
      scrolledUnderElevation: scrolledUnderElevation,
      shadowColor: Colors.black,
      systemOverlayStyle: systemOverlayStyle,
      surfaceTintColor:
          backgroundColor ??
          (!transparentType ? AppColors.foundationWhite : Colors.transparent),
      elevation: elevation,
      backgroundColor:
          backgroundColor ?? (!transparentType ? null : Colors.transparent),
      leadingWidth: isLeading ? leadingSlotWidth : null,
      titleSpacing: isLeading ? 0 : null,
      leading: isLeading
          ? Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () {
                  Navigator.maybePop(context);
                },
                child: Container(
                  color: Colors.transparent,
                  padding: EdgeInsets.fromLTRB(leadingLeftInset, 6, 6, 6),
                  child: UIHelper.responsiveIcon(
                    kIsWeb || Platform.isIOS
                        ? Icon(
                            CupertinoIcons.back,
                            color: foregroundColor ?? AppColors.foundationBlack,
                            //size: AppDimens.spMin20,
                          )
                        : SvgPicture.asset(
                            appBarType == AppBarType.typeLine
                                ? Assets.icons.arrowLeftIcon
                                : Assets.icons.arrowLeftWithoutLineIcon,
                            colorFilter: ColorFilter.mode(
                              foregroundColor ?? AppColors.foundationBlack,
                              BlendMode.srcIn,
                            ),
                            height: AppDimens.spMin20,
                            width: AppDimens.spMin20,
                          ),
                  ),
                ),
              ),
            )
          : null,
      title:
          titleWidget ??
          Text(
            title ?? 'Unknown',
            textAlign: TextAlign.center,
            // The one title style for every app bar: Onest medium 16/24.
            // Screens should not restate it — pass [foregroundColor] when the
            // bar's colour needs a different ink.
            style:
                titleStyle ??
                TextFontStyle.medium16sp.copyWith(
                  fontSize: AppDimens.spMin16,
                  height: 24 / 16,
                  letterSpacing: 0,
                  color: foregroundColor ?? AppColors.neutralColor.shade900,
                ),
          ),
      bottom: bottom,
      centerTitle: centerTitle,
    );
  }

  static TabBar tabBar({
    required TabController controller,
    required List<String> titleList,
    TextStyle? selected,
    TextStyle? unselected,
    void Function(int)? onTap,
    bool isScrollable = false,
    EdgeInsets? labelPadding,
  }) {
    return TabBar(
      onTap: onTap,
      dividerColor: Colors.transparent,
      labelStyle:
          selected ??
          TextFontStyle.medium16sp.copyWith(color: AppColors.primaryColor),
      unselectedLabelColor:
          unselected?.color ?? AppColors.neutralColor.shade600,
      indicatorColor: selected?.color ?? AppColors.primaryColor,
      labelColor: selected?.color ?? AppColors.primaryColor,
      indicatorSize: TabBarIndicatorSize.tab,
      controller: controller,
      unselectedLabelStyle:
          unselected ??
          TextFontStyle.medium16sp.copyWith(
            color: AppColors.neutralColor.shade600,
          ),
      padding: EdgeInsets.zero,
      labelPadding: labelPadding,
      tabAlignment: isScrollable ? TabAlignment.start : null,
      isScrollable: isScrollable,
      tabs: titleList
          .map(
            (e) => Padding(padding: const EdgeInsets.all(10), child: Text(e)),
          )
          .toList(),
    );
  }

  static Widget tabIconBar({
    required TabController controller,
    required List<(String selectedIconPath, String unselectedIconPath)>
    iconList,
    TextStyle? selected,
    TextStyle? unselected,
    bool isScrollable = false,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: controller.animation!,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: iconList.mapIndexed((index, e) {
                final selectedIcon =
                    (((controller.animation?.value ?? 0) - index).abs()) < 0.5;
                return InkWell(
                  onTap: () {
                    controller.animateTo(index);
                  },
                  child: iconUi(selectedIcon ? e.$1 : e.$2, selectedIcon),
                );
              }).toList(),
            );
          },
        ),
        AnimatedBuilder(
          animation: controller.animation!,
          builder: (context, child) {
            //double left = 30.0 * controller.index;

            // Use animation to interpolate the position
            final left = 76.0 * controller.animation!.value;
            //log('value -- ${controller.animation?.value}');
            return Positioned(left: left, bottom: 0, child: child!);
          },
          child: Container(
            width: 76,
            height: 2,
            color: AppColors.primaryColor.shade600,
          ),
        ),
      ],
    );
  }

  static Widget iconUi(String iconPath, bool setColor) {
    return Ink(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 26),
      child: SizedBox(
        child: SvgPicture.asset(
          iconPath,
          colorFilter: setColor
              ? const ColorFilter.mode(AppColors.primaryColor, BlendMode.srcIn)
              : null,
        ),
      ),
    );
  }
}
