import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/theme/app_dimens.dart';

import '../navigation/navigation_service.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_divider.dart';

/// Contains useful consts to reduce boilerplate and duplicate code
final class UIHelper {
  UIHelper._();

  static final media = MediaQuery.of(NavigationService.context);

  // Vertical spacing constants. Adjust to your liking.
  // static const double _verticalSpaceSmall = 10;
  // static const double _verticalSpaceMedium = 20;
  // //ignore: unused_field
  // static const double _verticalSpaceMediumLarge = 25;
  // static const double _verticalSpaceLarge = 60;
  // static const double _verticalSpaceExtraLarge = 100;
  // static const double _verticalSpaceSemiLarge = 40;
  //
  // //Vertical spacing constants. Adjust to your liking.
  // static const double _horizontalSpaceSmall = 10;
  // static const double _horizontalSpaceMedium = 20;
  // static const double _horizontalSpaceSemiLarge = 40;
  // static const double _horizontalSpaceLarge = 60;

  // static Widget verticalSpaceSmall = const SizedBox(height: _verticalSpaceSmall);
  // static Widget verticalSpaceMedium = const SizedBox(height: _verticalSpaceMedium);
  // static Widget verticalSpaceMediumLarge = const SizedBox(height: _verticalSpaceMediumLarge);
  // static Widget verticalSpaceSemiLarge = const SizedBox(height: _verticalSpaceSemiLarge);
  // static Widget verticalSpaceLarge = const SizedBox(height: _verticalSpaceLarge);
  // static Widget verticalSpaceExtraLarge = const SizedBox(height: _verticalSpaceExtraLarge);
  //
  // static Widget horizontalSpaceSmall = const SizedBox(width: _horizontalSpaceSmall);
  // static Widget horizontalSpaceMedium = const SizedBox(width: _horizontalSpaceMedium);
  // static Widget horizontalSpaceSemiLarge = const SizedBox(width: _horizontalSpaceSemiLarge);
  // static Widget horizontalSpaceLarge = const SizedBox(width: _horizontalSpaceLarge);

  static Widget horizontalSpace(double width) => SizedBox(width: width);

  static Widget verticalSpace(double height) => SizedBox(height: height);

  static final SizedBox verticalSpace4 = SizedBox(height: AppDimens.height4);
  static final SizedBox verticalSpace6 = SizedBox(height: AppDimens.height6);
  static final SizedBox verticalSpace8 = SizedBox(height: AppDimens.height8);
  static final SizedBox verticalSpace12 = SizedBox(height: AppDimens.height12);
  static final SizedBox verticalSpace16 = SizedBox(height: AppDimens.height16);
  static final SizedBox verticalSpace18 = SizedBox(height: AppDimens.height18);
  static final SizedBox verticalSpace20 = SizedBox(height: AppDimens.height20);
  static final SizedBox verticalSpace24 = SizedBox(height: AppDimens.height24);
  static final SizedBox verticalSpace32 = SizedBox(height: AppDimens.height32);
  static final SizedBox verticalSpace40 = SizedBox(height: AppDimens.height40);
  static final SizedBox verticalSpace48 = SizedBox(height: AppDimens.height48);

  static final SizedBox horizontalSpace4 = SizedBox(width: AppDimens.width4);
  static final SizedBox horizontalSpace8 = SizedBox(width: AppDimens.width8);
  static final SizedBox horizontalSpace12 = SizedBox(width: AppDimens.width12);
  static final SizedBox horizontalSpace16 = SizedBox(width: AppDimens.width16);
  static final SizedBox horizontalSpace20 = SizedBox(width: AppDimens.width20);

  //horizontal first and last will be vertical
  static const EdgeInsets paddingSymmetric16 = EdgeInsets.symmetric(
    horizontal: 16,
  );
  static const EdgeInsets padding16 = EdgeInsets.all(16);

  static final double safePadding = media.padding.top;

  static const Widget customDivider = CustomDivider();

  static Widget customDividerGet({double? endDent, double? indent}) =>
      CustomDivider(endDent: endDent, indent: indent);

  static Widget customDottedDivider = DottedLine(
    direction: Axis.horizontal,
    alignment: WrapAlignment.center,
    lineThickness: 1.0,
    dashLength: 4.0,
    dashColor: AppColors.neutralColor.shade300,
    dashRadius: 0.0,
    dashGapLength: 4.0,
    dashGapColor: Colors.transparent,
    dashGapRadius: 0.0,
  );

  //static double kDefaulutPadding() => 20.sp;

  static const EdgeInsets defaultPadding16_12 = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );

  static const EdgeInsets textIconBtnPadding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 12,
  );

  /// ActionButton take the padding
  static final BorderRadius borderRadius4r = BorderRadius.circular(4);

  static final BorderRadius borderRadius6r = BorderRadius.circular(6);

  static final BorderRadius borderRadius8r = BorderRadius.circular(8);

  static final BorderRadius borderRadius12r = BorderRadius.circular(12);

  static final BorderRadius borderRadius16r = BorderRadius.circular(16);
  static final BorderRadius borderRadius24r = BorderRadius.circular(24);

  static const Radius onlyRadius16r = Radius.circular(16);

  static const double kCustomBottomNavBarHeight = 80;

  static SizedBox responsiveIcon(Widget child, {double? size}) => SizedBox(
    height: size ?? AppDimens.spMin20,
    width: size ?? AppDimens.spMin20,
    child: child,
  );

  static const LinearProgressIndicator customLinearLoading =
      LinearProgressIndicator(
        color: AppColors.colorFoundationPrimary500,
        minHeight: 2,
      );
}
