import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';


import '../../gen/fonts.gen.dart';
import 'app_colors.dart';
import 'app_dimens.dart';

class ThemeManager {
  ThemeManager._();

  /// Deliberately NOT cached in a static field. The sizes below come from
  /// ScreenUtil (`AppDimens`, `.sp`, `.spMin`), which changes whenever
  /// `ScreenUtilInit` re-initialises — on the first real window metrics, on
  /// rotation, on split-screen. A cached ThemeData would freeze whatever
  /// scale happened to be active on the very first build, which is how you
  /// end up with correct sizes in debug and collapsed ones in release.
  /// This is only rebuilt when `ScreenUtilInit`'s builder re-runs, not per
  /// frame, so recomputing is cheap.
  static ThemeData getAppTheme() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.neutralColor.shade100,
      fontFamily: FontFamily.poppins,

      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryColor),
      // Text theme
      textTheme: TextTheme(
        titleLarge: TextStyle(
          color: AppColors.neutralColor.shade900,
          fontSize: AppDimens.spMin16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: AppColors.neutralColor.shade900,
          fontSize: AppDimens.spMin14,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: TextStyle(
          color: AppColors.neutralColor.shade900,
          fontSize: AppDimens.spMin14,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: AppColors.neutralColor.shade900,
          fontSize: AppDimens.spMin12,
          fontWeight: FontWeight.w500,
        ),
        labelMedium: TextStyle(
          color: AppColors.neutralColor.shade500,
          fontSize: AppDimens.spMin14,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: TextStyle(
          color: AppColors.neutralColor.shade600,
          fontSize: AppDimens.spMin12,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: AppColors.foundationWhite,
          fontSize: AppDimens.spMin16,
          fontWeight: FontWeight.w500,
        ),
        displaySmall: TextStyle(
          color: AppColors.neutralColor.shade900,
          fontSize: 15.spMin,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.foundationWhite,
      ),

      // AppBar theme
      appBarTheme: AppBarTheme(
        titleTextStyle: TextStyle(
          color: AppColors.neutralColor.shade900,
          fontSize: 16.sp,
          fontWeight: FontWeight.w500,
        ),
        iconTheme: IconThemeData(color: AppColors.neutralColor.shade500),
        // No titleSpacing override on purpose. It is the gap *after the
        // leading widget*, and Flutter measures it from the left edge when
        // there is no leading (NavigationToolbar: leadingWidth defaults to
        // 0). A negative value tuned for the back-button case therefore
        // pushed the title off-screen on every app bar without one, clipping
        // the first glyph. Material's default 16 is correct for both.
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        // statusBarIconBrightness is Android-only, statusBarBrightness is
        // iOS-only (and inverted: describes the background, not the icon
        // color) — both are needed or iOS ignores this entirely.
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
      ),
      // Input decoration theme section
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppDimens.radius16,
          vertical: AppDimens.radius13,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          color: AppColors.neutralColor.shade500,
          fontSize: AppDimens.spMin14,
          fontWeight: FontWeight.w400,
        ),
        hintStyle: TextStyle(
          color: AppColors.neutralColor.shade500,
          fontSize: AppDimens.spMin14,
          fontWeight: FontWeight.w400,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radius4),
          borderSide: BorderSide(
            color: AppColors.neutralColor.shade300,
            width: AppDimens.width1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radius4),
          borderSide: BorderSide(
            color: AppColors.primaryColor.shade400,
            width: AppDimens.width1,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radius4),
          borderSide: BorderSide(
            color: AppColors.errorColor.shade400,
            width: AppDimens.width1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radius4),
          borderSide: BorderSide(
            color: AppColors.errorColor.shade400,
            width: AppDimens.width1,
          ),
        ),
      ),

      // Dialogue BG color
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.foundationWhite,
      ),
      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.neutralColor.shade400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radius4),
          ),
          elevation: 0,
          splashFactory: NoSplash.splashFactory,
          padding: EdgeInsets.symmetric(
            horizontal: AppDimens.radius16,
            vertical: AppDimens.radius12,
          ),
          textStyle: TextStyle(
            color: AppColors.foundationWhite,
            fontSize: 16.spMin,
          ),
        ),
      ),

      // Date picker theme
      datePickerTheme: DatePickerThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppDimens.radius16)),
          side: BorderSide.none,
        ),
        backgroundColor: AppColors.foundationWhite,
        dividerColor: AppColors.primaryColor.shade500,
        todayBorder: BorderSide.none,
        dayBackgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primaryColor.shade500
              : Colors.transparent,
        ),
        dayForegroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.foundationWhite
              : AppColors.neutralColor.shade600,
        ),

        // confirmButtonStyle: ButtonStyle(
        //   shape: MaterialStateProperty.all<RoundedRectangleBorder>(
        //     RoundedRectangleBorder(
        //       borderRadius: BorderRadius.circular(10.r),
        //     ),
        //   ),
        //   backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
        //     return AppColor.colorPrimary; // Normal color
        //   }),
        //   foregroundColor: MaterialStateProperty.all(Colors.white),
        //   // Text color
        //   padding: MaterialStateProperty.all(
        //       EdgeInsets.symmetric(vertical: 10.r, horizontal: 30.r)),
        //   textStyle: MaterialStateProperty.all(
        //     TextStyle(
        //       color: Colors.white,
        //       fontSize: 16.sp,
        //       fontFamily: 'Roboto',
        //       fontWeight: FontWeight.w600,
        //     ),
        //   ),
        // ),
        // cancelButtonStyle: ButtonStyle(
        //   shape: MaterialStateProperty.all<RoundedRectangleBorder>(
        //     RoundedRectangleBorder(
        //       borderRadius: BorderRadius.circular(10.r),
        //     ),
        //   ),
        //   backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
        //     return AppColor.neutralColors300;
        //   }),
        //   foregroundColor:
        //   MaterialStateProperty.all(AppColor.colorBlackMidEmp2),
        //   // Text color
        //   padding: MaterialStateProperty.all(
        //       EdgeInsets.symmetric(vertical: 10.r, horizontal: 30.r)),
        //   textStyle: MaterialStateProperty.all(
        //     TextStyle(
        //       color: Colors.white,
        //       fontSize: 16.sp,
        //       fontFamily: 'Roboto',
        //       fontWeight: FontWeight.w600,
        //     ),
        //   ),
        // ),
      ),
      // Circular progress indicator theme
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primaryColor.shade500,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 2.0,
        // Track height (bar height)
        thumbShape: const PaddleSliderValueIndicatorShape(),
        // Custom thumb size
        activeTrackColor: AppColors.primaryColor,
        // Active track color
        inactiveTrackColor: Colors.grey,
        // Inactive track color
        thumbColor: AppColors.primaryColor,
        // Thumb color
        overlayColor: AppColors.primaryColor.withAlpha(32),
        //trackShape: const RectangularSliderTrackShape(),
        // Thumb overlay color (when pressed)
        // overlayShape:
        //     RoundSliderOverlayShape(overlayRadius: 20.0), // Overlay size
      ),
    );
  }
}
