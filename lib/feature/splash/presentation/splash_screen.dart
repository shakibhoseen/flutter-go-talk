import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:whatsapp_flutter_go/core/di/di.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/auth_routes.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/chat_routes.dart';
import 'package:whatsapp_flutter_go/core/session/session_cubit.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';

/// Always shown on launch. By the time this builds, `AppStartup` has already
/// restored the session and synced [SessionCubit] — so this is purely a
/// branding pause before routing to login or home based on that state.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decideNextRoute();
  }

  Future<void> _decideNextRoute() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    final isAuthenticated = locator<SessionCubit>().state.isAuthenticated;
    NavigationService.removeALlAndReplace(
      isAuthenticated ? ChatRoutes.home : AuthRoutes.login,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryColor,
      body: const Center(
        child: FaIcon(
          FontAwesomeIcons.whatsapp,
          color: Colors.white,
          size: 72,
        ),
      ),
    );
  }
}
