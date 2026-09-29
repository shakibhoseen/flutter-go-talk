import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../extension/text_style_extension.dart';
import '../helper/my_ui_import.dart';
import '../theme/app_dimens.dart';

enum CustomButtonType { fill, outline, textBtn }

class CustomActionButton extends StatelessWidget {
  const CustomActionButton({
    super.key,
    this.title,
    this.style,
    this.fontSize,
    this.titleColor,
    this.rightIcon,
    this.onTap,
    this.backgroundColor,
    this.padding,
    this.disable,
    this.borderRadius,
    this.loading,
    this.buttonType = CustomButtonType.fill,
    this.child,
    this.splashColor,
    this.borderColor,
    this.loadingColor,
    this.disableColor,
    this.disableTextColor,
    this.disableBorderColor,
  });
  final Widget? child;
  final String? title;
  final TextStyle? style;
  final double? fontSize;
  final Color? titleColor,
      backgroundColor,
      splashColor,
      borderColor,
      loadingColor,
      disableColor,
      disableTextColor,
      disableBorderColor;
  final bool? rightIcon, loading;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final bool? disable;
  final double? borderRadius;
  final CustomButtonType? buttonType;

  @override
  Widget build(BuildContext context) {
    return button();
  }

  Widget button() {
    final textWidget = Text(
      title ?? 'Title',
      textAlign: TextAlign.center,
      style:
          style.setColor(
            ((disable ?? false) && disableTextColor != null)
                ? disableTextColor!
                : style?.color ?? AppColors.neutralColor,
          ) ??
          TextStyle(fontSize: AppDimens.spMin16).copyWith(
            fontSize: fontSize,
            color: (disable ?? false)
                ? disableTextColor
                : titleColor ??
                      (buttonType == CustomButtonType.outline ||
                              buttonType == CustomButtonType.textBtn
                          ? AppColors.primaryColor
                          : Colors.white),
          ),
    );
    final haveBorder =
        buttonType == CustomButtonType.outline || borderColor != null;
    final paddingV =
        padding ??
        EdgeInsets.symmetric(
          vertical: AppDimens.spMin12,
          horizontal: AppDimens.spMin16,
        );
    final topP = paddingV.top - 1.spMin;
    final bottomP =
        paddingV.bottom -
        1; // when border and without border i want to same height button
    final resultP = haveBorder
        ? paddingV.copyWith(
            top: topP >= 0 ? topP : 0,
            bottom: bottomP >= 0 ? bottomP : 0,
          )
        : paddingV;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius ?? AppDimens.radius4),
      child: Ink(
        decoration: BoxDecoration(
          color: disable ?? false
              ? (disableColor ?? AppColors.neutralColor.shade400)
              : backgroundColor ??
                    (buttonType == CustomButtonType.outline
                        ? AppColors.primaryColor.shade50
                        : buttonType == CustomButtonType.fill
                        ? AppColors.primaryColor
                        : null),
          borderRadius: BorderRadius.circular(borderRadius ?? 4),
          border: buttonType == CustomButtonType.outline
              ? Border.all(
                  color: ((disable ?? false) && disableBorderColor != null)
                      ? disableBorderColor!
                      : borderColor ?? AppColors.primaryColor,
                )
              : borderColor != null
              ? Border.all(color: borderColor!)
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius ?? 4),
          splashColor:
              splashColor ??
              (buttonType == CustomButtonType.outline
                  ? AppColors.primaryColor.shade200
                  : buttonType == CustomButtonType.fill
                  ? null
                  : AppColors.primaryColor.shade50),
          onTap: (disable ?? false) || (loading ?? false)
              ? null
              : () {
                  if (onTap != null) {
                    onTap!();
                  }
                },
          child: Padding(
            padding: resultP,
            child:
                child ??
                ((rightIcon ?? false) || (loading ?? false)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          textWidget,
                          const SizedBox(width: 15),
                          loading ?? false
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      loadingColor ?? Colors.white,
                                    ),
                                    // Custom color
                                    strokeWidth: 2,
                                    // Custom thickness
                                    strokeCap: StrokeCap.round,
                                  ),
                                )
                              : const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: Icon(Icons.keyboard_arrow_left),
                                  //SvgPicture.asset(Assets.icons.arrowLeftIcon),
                                ),
                        ],
                      )
                    : textWidget),
          ),
        ),
      ),
    );
  }
}
