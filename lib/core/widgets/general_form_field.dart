import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../helper/ui_helpers.dart';
import '../theme/app_colors.dart';
import '../theme/text_font_style.dart';

enum ValidateRegisterInputType { name, phone, otp, password, emailPhone, email }

TextInputType _getInputType(ValidateRegisterInputType validate) {
  switch (validate) {
    case ValidateRegisterInputType.phone:
      return TextInputType.phone;
    case ValidateRegisterInputType.email:
      return TextInputType.emailAddress;
    case ValidateRegisterInputType.otp:
      return TextInputType.number;
    default:
      return TextInputType.text;
  }
}

class GeneralFormField extends StatelessWidget {
  GeneralFormField({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.onFiledSubmit,
    this.focus,
    this.validate = false,
    this.suffixIcon,
    this.validateType = ValidateRegisterInputType.name,
    this.validatorFunction,
    this.prefixIcon,
    this.disable = false,
    this.autofocus = false,
    this.expand,
    this.fillColor,
    this.borderRadius,
    this.label,
    this.textStyle,
    this.initialValue,
    this.onTapOutSide,
    this.cursorHeight,
    this.inputConstraint,
    this.autovalidateMode,
    this.inputFormatter,
  }) : textInputType = _getInputType(validateType);

  final TextEditingController? controller;
  final String? hintText, label, initialValue;
  final TextInputType textInputType;
  final void Function(String value)? onChanged;
  final void Function(String? value)? onFiledSubmit;
  final FocusNode? focus;
  final bool validate, disable, autofocus;
  final String? suffixIcon, prefixIcon;
  final ValidateRegisterInputType validateType;
  final String? Function(String? text)? validatorFunction;
  final bool? expand;
  final Color? fillColor;
  final double? borderRadius;
  final TextStyle? textStyle;
  final double? cursorHeight;
  final BoxConstraints? inputConstraint;
  final List<TextInputFormatter>? inputFormatter;
  final void Function(PointerDownEvent event)? onTapOutSide;
  final AutovalidateMode? autovalidateMode;

  // New parameter to control validation

  Widget _buildLabelWithRedAsterisks(String label) {
    final parts = label.split('*');
    if (parts.length == 1) {
      // No asterisk, return regular text
      return Text(
        label,
        style: TextFontStyle.regular14sp.copyWith(
          color: AppColors.neutralColor.shade400,
        ),
      );
    }

    // Build RichText with red asterisks
    final spans = <TextSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        spans.add(
          TextSpan(
            text: parts[i],
            style: TextFontStyle.regular14sp.copyWith(
              color: AppColors.neutralColor.shade400,
            ),
          ),
        );
      }
      if (i < parts.length - 1) {
        spans.add(
          TextSpan(
            text: '*',
            style: TextFontStyle.regular14sp.copyWith(
              color: AppColors.errorColor,
            ),
          ),
        );
      }
    }

    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius != null
        ? BorderRadius.circular(borderRadius!)
        : UIHelper.borderRadius4r;
    return TextFormField(
      autofocus: autofocus,
      onTapOutside: onTapOutSide,
      initialValue: initialValue,
      cursorColor: AppColors.primaryColor,
      cursorHeight: cursorHeight,
      autovalidateMode: autovalidateMode,
      textAlignVertical: (expand ?? false) ? TextAlignVertical.top : null,
      maxLines: (expand ?? false) ? null : 1,
      onFieldSubmitted: (value) {
        if (onFiledSubmit == null) {
          return;
        }
        onFiledSubmit!(value);
      },
      expands: expand ?? false,
      enabled: !disable,
      focusNode: focus,
      onChanged: onChanged,
      controller: controller,
      keyboardType: textInputType,
      inputFormatters: inputFormatter,
      style:
          textStyle ??
          TextFontStyle.regular14sp.copyWith(
            color: AppColors.neutralColor.shade900,
          ),
      decoration: InputDecoration(
        label: label == null ? null : _buildLabelWithRedAsterisks(label!),
        suffixIcon: suffixIcon != null
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SvgPicture.asset(
                  suffixIcon!,
                  colorFilter: ColorFilter.mode(
                    disable
                        ? AppColors.neutralColor.shade300
                        : AppColors.neutralColor,
                    BlendMode.srcIn,
                  ),
                ),
              )
            : null,
        prefixIcon: prefixIcon != null
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: Center(
                    child: SvgPicture.asset(
                      prefixIcon!,
                      colorFilter: ColorFilter.mode(
                        disable
                            ? AppColors.neutralColor.shade300
                            : AppColors.neutralColor,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        hintText: hintText,
        hintStyle: (textStyle ?? TextFontStyle.regular14sp).copyWith(
          color: AppColors.neutralColor.shade400,
        ),
        //labelStyle: TextStyle(fontSize: 16.sp),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            width: 1,
            color: AppColors.neutralColor.shade300,
          ),
          borderRadius: radius,
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            width: 1,
            color: AppColors.primaryColor.shade400,
          ),
          borderRadius: radius,
        ),
        contentPadding: const EdgeInsets.all(10),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            width: 1,
            color: AppColors.neutralColor.shade300,
          ),
          borderRadius: radius,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(width: 1, color: AppColors.errorColor),
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide(
            width: 1,
            color: AppColors.neutralColor.shade400,
          ),
          borderRadius: radius,
        ),
        fillColor: fillColor,
        filled: fillColor != null,
        prefixIconConstraints: BoxConstraints.loose(const Size.fromHeight(40)),
        constraints: inputConstraint,
      ),
      validator: disable
          ? null
          : validatorFunction ??
                (validate ? _getValidator(validateType) : null),
    );
  }

  String? Function(String?) _getValidator(ValidateRegisterInputType validate) {
    switch (validate) {
      case ValidateRegisterInputType.password:
        return _validatePassword;
      case ValidateRegisterInputType.phone:
        return _validatePhoneNumber;
      case ValidateRegisterInputType.emailPhone:
        return _validateEmailPhoneNumber;
      case ValidateRegisterInputType.email:
        return _validateEmail;

      default:

        /// both otp and name should be anything just make sure they are not empty that's enough
        return _validateText;
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 7) {
      return 'password should be at least 8 character';
    }
    return null;
  }

  String? _validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    // if (!RegExp(r'^\+\d+$').hasMatch(value)) {
    //   return 'Please enter a valid phone number with country code';
    // }
    if (!RegExp(
      r'(^([+]{1}[8]{2}|88)?(01){1}[3-9]{1}\d{8})$',
    ).hasMatch(value)) {
      return 'Please enter a valid phone number with country code';
    }
    return null;
  }

  String? _validateEmailPhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone or email';
    }
    final phoneOrEmailRegExp = RegExp(
      r'^((\+8801|8801|01)?\d{9})$|([\w.-]+@[\w.-]+\.\w{2,3})$',
    );
    if (!phoneOrEmailRegExp.hasMatch(value)) {
      return 'Please enter a valid phone or email';
    }
    return null;
  }

  String? _validateText(String? value) {
    if (value == null || value.isEmpty) {
      return 'This field cannot be empty';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email address';
    }
    if (!_isValidEmail(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  bool _isValidEmail(String email) {
    // Regular expression pattern for validating email addresses
    final regex = RegExp(r'^[\w.-]+@[a-zA-Z\d.-]+\.[a-zA-Z]{2,}$');
    return regex.hasMatch(email);
  }
}
