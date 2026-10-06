import 'dart:developer';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../core/db/network/dio/auth_dio.dart';
import '../../core/db/network/dio/dio.dart';
import '../../core/db/network/socket/chat_socket_service.dart';
import '../../core/di/di.dart';
import '../../core/session/auth_bootstrap.dart';
import '../../core/session/auth_session.dart';
import '../../core/session/session_cubit.dart';
import '../../feature/chat_inbox/data/outbox/chat_sync_coordinator.dart';
import '../app_version/app_version_service.dart';

class AppStartup {
  static Future<void> initialize() async {
    // Hosts live in `.env`, so nothing that resolves a base url may run before
    // this. A missing file must not stop the app — the flavor defaults in
    // AppFlavorConfig cover it.
    try {
      await dotenv.load(fileName: '.env');
    } catch (error) {
      // Falls back to AppFlavorConfig's defaults — but a silent catch here
      // once hid a real bug (`.env` missing from pubspec's `assets:`) for a
      // long time, so at least say so in the log.
      log('could not load .env: $error', name: 'AppStartup');
    }

    await Future.wait([AppVersionService.init(), diSetup()]);

    AuthDioSingleton.instance.create();
    // The general/chat client — created here too so a guest's first request
    // (before any login) doesn't hit it uninitialized.
    DioSingleton.instance.create();
    // Before the first frame, so a returning user is already signed in when
    // the profile tab is first tapped.
    await AuthBootstrap.restoreSession();

    // SessionCubit is the single source of truth the rest of the app reads
    // (splash's routing decision, SessionResetScope) — sync it from whatever
    // AuthBootstrap just restored from disk.
    locator<SessionCubit>().sync(
      isLoggedIn: AuthSession.isSignedIn,
      accessToken: AuthSession.accessToken,
    );

    if (AuthSession.isSignedIn) {
      ChatSyncCoordinator.instance.start();
      ChatSocketService.instance.connect();
    }
  }
}
