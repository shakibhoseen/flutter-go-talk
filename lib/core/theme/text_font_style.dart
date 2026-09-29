import 'package:flutter/material.dart';


import '../../gen/fonts.gen.dart';
import 'app_colors.dart';

class TextFontStyle {
  TextFontStyle._();

  static TextStyle get medium10sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w500,
    fontSize: 10,
  );

  static TextStyle get regular10sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w400,
    fontSize: 10,
  );

  static TextStyle get medium12sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w500,
    fontSize: 12,
  );

  static TextStyle get regular12sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w400,
    fontSize: 12,
  );

  static TextStyle get medium14sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w500,
    fontSize: 14,
  );

  static TextStyle get regular14sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w400,
    fontSize: 14,
  );

  static TextStyle get medium16sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w500,
    fontSize: 16,
  );

  static TextStyle get medium18sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w500,
    fontSize: 18,
  );

  static TextStyle get regular16sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w400,
    fontSize: 16,
  );

  static TextStyle get medium20sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w500,
    fontSize: 20,
  );

  static TextStyle get bold20sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w700,
    fontSize: 20,
  );

  static TextStyle get bold32sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w700,
    fontSize: 32,
  );

  static TextStyle get bold18sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w700,
    fontSize: 18,
  );

  static TextStyle get medium24sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w500,
    fontSize: 24,
  );

  static TextStyle get semi24sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w600,
    fontSize: 24,
  );

  static TextStyle get semi14sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );

  static TextStyle get semi16sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w600,
    fontSize: 16,
  );

  static TextStyle get semi18sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w600,
    fontSize: 18,
  );

  static TextStyle get semi12sp => const TextStyle(
    fontFamily: FontFamily.poppins,
    fontWeight: FontWeight.w600,
    fontSize: 12,
  );
}

class MyTextTheme {
  MyTextTheme({required this.base});
  final TextTheme base;

  TextTheme get theme => TextTheme(
    titleSmall: base.titleSmall?.copyWith(
      color: AppColors.neutralColor.shade900,
    ),
    titleMedium: base.titleMedium?.copyWith(
      color: AppColors.neutralColor.shade900,
    ),
    titleLarge: base.titleLarge?.copyWith(
      color: AppColors.neutralColor.shade900,
    ),
    bodySmall: base.bodySmall?.copyWith(color: AppColors.neutralColor.shade600),
    bodyMedium: base.bodyMedium?.copyWith(
      color: AppColors.neutralColor.shade600,
    ),
    bodyLarge: base.bodyLarge?.copyWith(color: AppColors.neutralColor.shade600),
    labelSmall: base.labelSmall?.copyWith(
      color: AppColors.neutralColor.shade900,
    ),
    labelMedium: base.labelMedium?.copyWith(
      color: AppColors.neutralColor.shade900,
    ),
    labelLarge: base.labelLarge?.copyWith(
      color: AppColors.neutralColor.shade900,
    ),
  );
}
