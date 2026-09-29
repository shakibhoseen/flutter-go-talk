import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Single source of truth for status-bar style, applied imperatively via
/// [SystemChrome.setSystemUIOverlayStyle] instead of `AnnotatedRegion`.
///
/// `AnnotatedRegion` is declarative and lives in the widget tree, which is
/// fine when there's exactly one "screen" active at a time — but this app
/// has two different kinds of screen switches that don't fit that model:
/// - Bottom-nav tabs live in one `PageView`, so more than one tab's
///   `AnnotatedRegion` can be mounted at once (only one is visible).
/// - Pushing a route on top of the tab shell doesn't clear the shell's
///   `AnnotatedRegion` — if the pushed screen doesn't declare its own, the
///   shell's leaks through (e.g. push from the dark reel tab and the new
///   screen stays dark).
///
/// Calling `SystemChrome` directly, driven by [NavBlocCubit] (tab changes)
/// and [AppNavigatorObserver] (route push/pop), sidesteps both problems —
/// there's exactly one imperative call per navigation event, always for
/// whatever is actually on top right now.
class AppStatusBar {
  AppStatusBar._();

  /// For screens with a light/white background — dark (visible) icons.
  static const forLightBackground = SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    statusBarColor: AppColors.foundationWhite,
  );

  /// For screens with a dark/black background — light (visible) icons.
  static const forDarkBackground = SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    statusBarColor: AppColors.foundationBlack,
  );

  /// For screens that paint their own background up under the bar — the bar
  /// gets no colour of its own, and light icons sit over whatever the screen
  /// has put there.
  ///
  /// Android is the only platform this exists for. Its status bar has a
  /// background of its own, and [SystemUiOverlayStyle.light] leaves that
  /// background alone (`statusBarColor` is null on it), so a screen that only
  /// asks for light icons keeps whichever colour the last screen set — white
  /// icons on a white bar, invisible. On iOS the bar has never had a colour;
  /// the screen already shows through, which is why the two platforms looked
  /// different for the same code.
  static const overOwnBackground = SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    statusBarColor: Colors.transparent,
  );

  /// For a screen whose bar carries a colour of its own: the status bar takes
  /// the same colour, and the icons take whichever brightness stays legible on
  /// it. For colours that come from data — a section's own branding, say —
  /// where no constant above can be used.
  ///
  /// Pairs with [overOwnBackground], which is the other half of the same
  /// problem: there the screen paints under the bar and it should have no
  /// colour; here the bar is a band of its own and the status bar should
  /// continue it. What must not happen in either case is leaving Android's
  /// status-bar colour to whatever the previous screen set, which is what
  /// [SystemUiOverlayStyle.light] and `.dark` do — they set icons only.
  static SystemUiOverlayStyle matching(Color background) {
    final isDark =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: background,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    );
  }

  static void apply(SystemUiOverlayStyle style) =>
      SystemChrome.setSystemUIOverlayStyle(style);
}
