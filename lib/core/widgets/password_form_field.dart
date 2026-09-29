import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../../gen/assets.gen.dart';
import '../extension/context_extension.dart';
import '../helper/keyboard.dart';
import '../helper/ui_helpers.dart';
import '../theme/app_colors.dart';
import '../theme/text_font_style.dart';

class PasswordFormField extends StatelessWidget {
  const PasswordFormField({
    super.key,
    required this.controller,
    this.hintText,
    required this.currentFocusNode,
    this.nextFocusNode,
    this.prefixIcon,
    this.disable = false,
    this.disableObscure = false,
    this.validatorFunction,
    this.fillColor,
    this.label,
    this.onChanged,
    this.forceErrorText,
    this.errorMaxLines,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String? hintText, label;
  final FocusNode currentFocusNode;
  final FocusNode? nextFocusNode;
  final String? prefixIcon;
  final bool disable, disableObscure;
  final String? Function(String?)? validatorFunction;
  final Color? fillColor;
  final String? forceErrorText;
  final int? errorMaxLines;

  @override
  Widget build(BuildContext context) {
    final obscureProvider = ValueNotifier(true);
    return ValueListenableBuilder(
      valueListenable: obscureProvider,
      builder: (context, obscureValue, child) {
        return TextFormField(
          cursorColor: AppColors.primaryColor,
          onChanged: (val) {
            if (onChanged != null) {
              onChanged!(val);
            }
          },
          enabled: !disable,
          focusNode: currentFocusNode,
          controller: controller,
          keyboardType: TextInputType.text,
          style: context.textTheme.labelMedium?.copyWith(
            color: AppColors.neutralColor.shade900,
          ),
          onFieldSubmitted: (_) {
            KeyboardUtil.shiftFocus(context, currentFocusNode, nextFocusNode);
          },
          decoration: InputDecoration(
            errorMaxLines: errorMaxLines,
            label: label == null
                ? null
                : Text(
                    '$label',
                    style: TextFontStyle.regular14sp.copyWith(
                      color: AppColors.neutralColor.shade400,
                    ),
                  ),
            prefixIcon: prefixIcon != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: SvgPicture.asset(
                        prefixIcon!,
                        colorFilter: ColorFilter.mode(
                          disable
                              ? AppColors.neutralColor.shade300
                              : AppColors.neutralColor.shade400,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  )
                : null,
            hintText: hintText,
            hintStyle: context.textTheme.labelMedium?.copyWith(
              color: AppColors.neutralColor.shade400,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: UIHelper.borderRadius4r,
              borderSide: BorderSide(
                width: 1,
                color: AppColors.neutralColor.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: UIHelper.borderRadius4r,
              borderSide: BorderSide(
                width: 1,
                color: AppColors.primaryColor.shade400,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: UIHelper.borderRadius4r,
              borderSide: BorderSide(
                width: 1,
                color: AppColors.neutralColor.shade300,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: UIHelper.borderRadius4r,
              borderSide: const BorderSide(
                width: 1,
                color: AppColors.errorColor,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: UIHelper.borderRadius4r,
              borderSide: BorderSide(
                width: 1,
                color: AppColors.neutralColor.shade400,
              ),
            ),
            contentPadding: const EdgeInsets.all(10),
            suffixIcon: disableObscure
                ? null
                : IconButton(
                    onPressed: () {
                      obscureProvider.value = !obscureProvider.value;
                    },
                    icon: SizedBox(
                      height: 24,
                      width: 24,
                      child: Center(
                        child: SvgPicture.asset(
                          !obscureValue
                              ? Assets.icons.visibilityOnIcon
                              : Assets.icons.eyeOffRealIcon,
                          colorFilter: ColorFilter.mode(
                            disable
                                ? AppColors.neutralColor.shade300
                                : AppColors.neutralColor.shade400,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
            fillColor: fillColor,
            filled: fillColor != null,
            suffixIconConstraints: BoxConstraints.loose(
              const Size.fromHeight(40),
            ),
          ),
          forceErrorText: forceErrorText,
          obscureText: obscureValue,
          validator: disable
              ? null
              : validatorFunction ??
                    (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (value.length < 8) {
                        return 'Password must be at least 8 characters';
                      }
                      return null;
                    },
        );
      },
    );
  }
}
