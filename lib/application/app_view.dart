import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../core/navigation/navigation_service.dart';
import '../core/navigation/routes/route_generator.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/theme_manager.dart';
import '../feature/splash/presentation/splash_screen.dart';

/// The app's root `MaterialApp` — trimmed down from the super-app template:
/// no deep links, play-store update gate or Ramadan overlay, none of which
/// apply here.
class AppView extends StatelessWidget {
  const AppView({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: MediaQuery.sizeOf(context).width > 600
          ? const Size(834, 1194)
          : const Size(393, 852),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'WhatsApp Go',
          theme: ThemeManager.getAppTheme(),
          builder: (context, child) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                statusBarIconBrightness: Brightness.dark,
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: AppColors.foundationWhite,
                systemNavigationBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          // `NavigationService.observer` is what `AutoRouteAware` reads to
          // find the current route; `routeObserver` is what it subscribes
          // through. Both must be the exact instances registered here.
          navigatorObservers: [
            NavigationService.observer,
            NavigationService.routeObserver,
          ],
          navigatorKey: NavigationService.navigatorKey,
          onGenerateRoute: RouteGenerator.generateRoute,
          home: const SplashScreen(),
        );
      },
    );
  }
}
