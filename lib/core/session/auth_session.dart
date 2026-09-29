import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../feature/login/model/login_response.dart';
import '../db/network/dio/auth_dio.dart';
import '../db/network/dio/dio.dart';
import 'auth_session_store.dart';

/// The signed-in session for this run.
///
/// Kept in memory for the run and on disk between runs (see
/// [AuthSessionStore]); [AuthBootstrap.restoreSession] brings it back at
/// startup. Every reader goes through this class, so persistence is the only
/// thing that had to know where the tokens live.
final class AuthSession {
  AuthSession._();

  static LoginResponse? _tokens;
  static DateTime? _accessTokenExpiry;

  /// Flips whenever a session starts or ends, so a screen built while the user
  /// was a guest can load its account data the moment they sign in — without
  /// every such screen having to know where login happened.
  static final ValueNotifier<bool> signedIn = ValueNotifier<bool>(false);

  static LoginResponse? get tokens => _tokens;

  static bool get isSignedIn => _tokens?.token?.isNotEmpty ?? false;

  static String? get accessToken => _tokens?.token;

  /// True once the access token's short life is up. The refresh token outlives
  /// it by a month, so this is the cue to refresh, not to sign out.
  static bool get isAccessTokenExpired {
    final expiry = _accessTokenExpiry;
    return expiry == null || !expiry.isAfter(DateTime.now());
  }

  /// Takes a fresh login (or refresh), points the client at it and stores it.
  static void start(LoginResponse response) {
    final expiry = DateTime.now().add(Duration(minutes: 30));
    adopt(response, accessExpiresAt: expiry);
    // Not awaited: a disk write must not sit between the user tapping Log in
    // and the app reacting. A failed write only costs them the next restart.
    unawaited(AuthSessionStore.write(response, expiry));
  }

  /// Installs a session without writing it back — for the one that just came
  /// *off* disk at startup.
  static void adopt(LoginResponse response, {DateTime? accessExpiresAt}) {
    _tokens = response;
    _accessTokenExpiry =
        accessExpiresAt ??
        DateTime.now().add(Duration(minutes: 30 ));
    AuthDioSingleton.instance.update(response.token);
    // `DioSingleton` (`GlobalDataApi`) is this app's general/chat client —
    // one backend, one bearer, unlike the multi-service split this app was
    // templated from where each service had its own separate auth.
    DioSingleton.instance.update(response.token);
    signedIn.value = true;
  }

  static void clear() {
    _tokens = null;
    _accessTokenExpiry = null;
    AuthDioSingleton.instance.update(null);
    DioSingleton.instance.update(null);
    signedIn.value = false;
    unawaited(AuthSessionStore.clear());
  }
}
