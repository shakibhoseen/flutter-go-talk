

import 'package:whatsapp_flutter_go/feature/chat_inbox/presentation/chat_inbox_screen.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/home_screen.dart';

import '../analytics/route_analytics_registry.dart';

class ChatRoutes {
  ChatRoutes._();

  static String home = '/chat/home';
  static String profile = '/chat/profile';
  static String inbox = '/chat/inbox';


  static final analytics = <String, RouteAnalyticsMeta>{
    home: const RouteAnalyticsMeta(screenName: 'chat_home', feature: 'chat'),

    profile: const RouteAnalyticsMeta(screenName: 'profile', feature: 'chat'),

  };

  static final routes = <String, AppRouteDefinition>{
    home: AppRouteDefinition(
      analytics: analytics[home]!,
      builder: (context, arguments) => const HomeScreen(),
    ),

    inbox: AppRouteDefinition(
      analytics: analytics[profile]!,
      builder: (context, arguments) => const ChatInboxScreen(),
    ),

  };
}
