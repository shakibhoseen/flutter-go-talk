
import '../../../feature/login/presentation/login_screen.dart';
import '../../../feature/singup/presentation/signup_screen.dart';
import '../analytics/route_analytics_registry.dart';

class AuthRoutes {
  AuthRoutes._();

  static const String login = '/auth/login';
  static const String register = '/auth/register';

  static final analytics = <String, RouteAnalyticsMeta>{
    login: const RouteAnalyticsMeta(screenName: 'login', feature: 'auth'),
    register: const RouteAnalyticsMeta(screenName: 'signup', feature: 'auth'),
  };

  static final routes = <String, AppRouteDefinition>{
    login: AppRouteDefinition(
      analytics: analytics[login]!,
      builder: (context, arguments) => const LoginScreen(),
    ),
    register: AppRouteDefinition(
      analytics: analytics[register]!,
      builder: (context, arguments) => const SignupScreen(),
    ),
  };
}
