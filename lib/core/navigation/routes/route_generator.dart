import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../analytics/route_analytics_registry.dart';
import 'auth_routes.dart';
import 'chat_routes.dart';

class RouteGenerator {
  RouteGenerator._();

  static Route<dynamic>? generateRoute(RouteSettings settings) {
    final routeName = settings.name;
    if (routeName != null) {
      final definition = _definitions[routeName];
      if (definition != null) {
        return _transitionRoute(
          settings: settings,
          page: (context) => definition.builder(context, settings.arguments),
        );
      }
    }

    return MaterialPageRoute(
      builder: (_) => Scaffold(
        body: Center(child: Text('No route defined for ${settings.name}')),
      ),
    );
  }

  static final Map<String, AppRouteDefinition> _definitions = {
    ...AuthRoutes.routes,
    ...ChatRoutes.routes,
  };

  static PageRoute _transitionRoute({
    required RouteSettings settings,
    required Widget Function(BuildContext context) page,
  }) {
    if (!kIsWeb && Platform.isIOS) {
      return CupertinoPageRoute(
        builder: (context) => page(context),
        settings: settings,
      );
    }

    return MaterialPageRoute(
      builder: (context) => page(context),
      settings: settings,
    );
  }
}
