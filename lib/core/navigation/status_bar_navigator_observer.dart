import 'package:flutter/material.dart';

import 'app_status_bar.dart';

/// NOT currently registered anywhere — [PacklyHomeScreen]'s `RouteAwareState`
/// already covers today's actual need (the shell is either covered by a
/// pushed screen or it isn't; nothing pushed is dark yet). Keep this around
/// for when that stops being true: e.g. a full-screen video/image viewer
/// gets pushed from somewhere and needs *its own* dark status bar regardless
/// of which tab it was pushed from.
///
/// To wire it back in: add it to `MaterialApp.navigatorObservers` in
/// main.dart, and list that route's name in [darkRouteNames]. Unlike the
/// RouteAwareState approach, this inspects *every* pushed route by name
/// (not just "is the shell covered"), so it also correctly restores a
/// specific route's own style when popping back to *it* (not just when
/// popping all the way back to the shell).
class StatusBarNavigatorObserver extends NavigatorObserver {
  StatusBarNavigatorObserver({this.darkRouteNames = const {}});

  final Set<String> darkRouteNames;

  void _apply(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name == Navigator.defaultRouteName) {
      //AppStatusBar.apply(tabStatusBarStyle(NavBlocCubit().currentIndex));
      return;
    }
    AppStatusBar.apply(
      darkRouteNames.contains(name)
          ? AppStatusBar.forDarkBackground
          : AppStatusBar.forLightBackground,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _apply(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _apply(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _apply(newRoute);
}
