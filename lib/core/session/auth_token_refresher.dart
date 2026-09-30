import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart';

import '../db/network/auth_endpoints.dart';
import '../db/network/network_base_url_resolver.dart';
import '../db/network/network_service_type.dart';
import '../config/app_flavor_config.dart';
import '../../feature/login/model/login_response.dart';
import 'auth_session.dart';

/// Trades the refresh token for a new access token.
///
/// Uses a bare [Dio] of its own rather than the app's auth client: that client
/// carries the interceptor which calls *this*, and a refresh that can 401 into
/// another refresh never stops.
final class AuthTokenRefresher {
  AuthTokenRefresher._();

  static final AuthTokenRefresher instance = AuthTokenRefresher._();

  Future<bool>? _inFlight;

  /// True when the session now holds a usable access token.
  ///
  /// Single-flight on purpose: a screen with four parallel calls gets four
  /// 401s at once, and four refreshes would race — the last one wins and the
  /// other three tokens are already revoked, signing the user out mid-screen.
  /// They all await the same attempt instead.
  Future<bool> refresh() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final attempt = _refresh();
    _inFlight = attempt;
    return attempt.whenComplete(() {
      _inFlight = null;
    });
  }

  Future<bool> _refresh() async {
    final refreshToken = AuthSession.tokens?.refreshToken ?? '';
    if (refreshToken.isEmpty) {
      log('no refresh token to trade', name: 'AuthTokenRefresher');
      return false;
    }

    // Logged by hand rather than through the shared `Logger` interceptor: the
    // request body *is* the refresh token, and the interceptor prints bodies.
    log('access token rejected, refreshing…', name: 'AuthTokenRefresher');
    
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: AppFlavorConfig.baseUrlFor(NetworkServiceType.auth),
          responseType: ResponseType.json,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: const {'Accept': 'application/json'},
        ),
      );
      final response = await dio.post(
        'auth/refresh',
        data: {'refresh_token': refreshToken},
      );
    
      final body = response.data;
      final data = body is Map ? body : null;
      if (data is! Map) {
        log('refresh response had no data block', name: 'AuthTokenRefresher');
        return false;
      }
    
      final refreshed = LoginResponse.fromJson(Map<String, dynamic>.from(data));
      if (!refreshed.hasTokens) {
        return false;
      }
      // The server rotates the refresh token too, so the whole pair is
      // replaced — keeping the old one would fail the next refresh.
      AuthSession.start(refreshed);
      log(
        'refreshed successfully',
        name: 'AuthTokenRefresher',
      );
      return true;
    } catch (error) {
      log('refresh failed: $error', name: 'AuthTokenRefresher');
      return false;
    }
  }
}
