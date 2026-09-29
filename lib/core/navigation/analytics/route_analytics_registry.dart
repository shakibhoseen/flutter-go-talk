import 'package:flutter/widgets.dart';

import '../routes/auth_routes.dart';
import '../routes/chat_routes.dart';

typedef AppRouteBuilder =
    Widget Function(BuildContext context, dynamic arguments);

class RouteAnalyticsMeta {
  const RouteAnalyticsMeta({
    required this.screenName,
    required this.feature,
    this.trackScreenView = true,
  });
  final String screenName;
  final String feature;
  final bool trackScreenView;
}

class RouteAnalyticsRegistry {
  RouteAnalyticsRegistry._();

  static final Map<String, RouteAnalyticsMeta> _registry = {
    ...AuthRoutes.analytics,
    ...ChatRoutes.analytics,
  };

  static RouteAnalyticsMeta resolve(String routeName) {
    return _registry[routeName] ??
        RouteAnalyticsMeta(
          screenName: normalizeRouteName(routeName),
          feature: inferFeature(routeName),
        );
  }

  static String normalizeRouteName(String routeName) {
    final normalized = routeName
        .trim()
        .replaceAll(RegExp(r'^[\/]+'), '')
        .replaceAll(RegExp(r'[/\s\-]+'), '_')
        .replaceAll(RegExp(r'(?<=[a-z0-9])([A-Z])'), r'_$1')
        .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .toLowerCase();

    return normalized.isEmpty ? 'unknown_screen' : normalized;
  }

  static String inferFeature(String routeName) {
    final normalized = routeName.trim().toLowerCase();
    if (normalized.startsWith('/auth/')) return 'auth';
    if (normalized.startsWith('/chat/')) return 'chat';
    return 'app';
  }
}

class AppRouteDefinition {
  const AppRouteDefinition({required this.builder, required this.analytics});
  final AppRouteBuilder builder;
  final RouteAnalyticsMeta analytics;
}
