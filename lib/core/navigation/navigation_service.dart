import 'package:flutter/material.dart';

/// Tracks the current route so [NavigationService.getArguments] can read it
/// back — a slim, dependency-free stand-in for the DI/Firebase-backed
/// observer used in the original app. Register this in `MaterialApp.navigatorObservers`.
class AppNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? currentRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    currentRoute = newRoute ?? oldRoute;
  }
}

final class NavigationService {
  NavigationService._internal();

  factory NavigationService() => _instance;
  static final NavigationService _instance = NavigationService._internal();

  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static final AppNavigatorObserver observer = AppNavigatorObserver();

  /// For `RouteAware` subscribers (see core/mixin/auto_route_aware.dart) —
  /// register this in `MaterialApp.navigatorObservers` too.
  static final RouteObserver<PageRoute> routeObserver =
      RouteObserver<PageRoute>();

  static Future<T?> pushModalRoute<T>(ModalRoute<T> route) =>
      navigatorKey.currentState!.push(route);

  static void removeModalRoute<T>(ModalRoute<T> route, [T? result]) =>
      navigatorKey.currentState!.removeRoute(route, result);

  static Future<T?> navigateTo<T>(String routeName) =>
      navigatorKey.currentState!.pushNamed<T>(routeName);

  static Future<dynamic> navigateToReplacement(String routeName) =>
      navigatorKey.currentState!.pushReplacementNamed(routeName);

  static Future<T?> popAndReplace<T, R>(
    String routeName, {
    Map<String, dynamic>? map,
    R? result,
  }) {
    return navigatorKey.currentState!.popAndPushNamed<T, R>(
      routeName,
      result: result,
      arguments: map,
    );
  }

  static Future<dynamic> removeALlAndReplace(String routeName) {
    return navigatorKey.currentState!.pushNamedAndRemoveUntil(
      routeName,
      (route) => false,
    );
  }

  static void removeUntil(String routeName) {
    navigatorKey.currentState?.popUntil((route) {
      if (route.settings.name == null) {
        return false;
      }
      return route.settings.name == routeName;
    });
  }

  static void removeFromTop(int count) async {
    assert(count > 0, 'Count must be positive');
    var base = -1;
    navigatorKey.currentState?.popUntil((route) {
      if (route.settings.name == null) {
        return false;
      }
      base++;
      return count <= base;
    });
  }

  static Future<T?> popAndReplaceWihArgs<T, R>(
    String routeName, {
    Map<String, dynamic>? map,
    R? result,
  }) => navigatorKey.currentState!.popAndPushNamed<T, R>(
    routeName,
    arguments: map,
    result: result,
  );

  static Future<T?> navigateToWithObject<T>(String routeName, Object? obj) =>
      navigatorKey.currentState!.pushNamed<T>(routeName, arguments: obj);

  static Future<bool>? goBack<N>({N? result}) =>
      navigatorKey.currentState?.maybePop(result);

  static void goStrictBack<N>({N? result}) =>
      navigatorKey.currentState?.pop(result);

  static Future<T?> popOneAndNavigateToWithObject<T>(
    String routeName,
    Object? obj,
  ) async {
    navigatorKey.currentState?.pop();
    await Future.delayed(const Duration(milliseconds: 100));
    return navigatorKey.currentState?.pushNamed<T>(routeName, arguments: obj);
  }

  static bool? get goBeBack => navigatorKey.currentState?.canPop();

  static BuildContext get context {
    assert(
      navigatorKey.currentContext != null,
      'Navigator context is not available',
    );
    return navigatorKey.currentContext!;
  }

  static T? getArguments<T>() {
    final args = observer.currentRoute?.settings.arguments;
    if (args is T) {
      return args;
    }
    return null;
  }
}
