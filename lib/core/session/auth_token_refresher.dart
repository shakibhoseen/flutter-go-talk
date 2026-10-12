import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../db/network/network_service_type.dart';
import '../config/app_flavor_config.dart';
import '../../feature/login/model/login_response.dart';
import 'auth_session.dart';

enum TokenRefreshResult {
  success,
  invalidToken,
  networkError,
  stale,
}

/// Trades the refresh token for a new access token.
///
/// Uses a bare [Dio] of its own rather than the app's auth client: that client
/// carries the interceptor which calls *this*, and a refresh that can 401 into
/// another refresh never stops.
final class AuthTokenRefresher {
  AuthTokenRefresher._();

  static final AuthTokenRefresher instance = AuthTokenRefresher._();

  @visibleForTesting
  static Dio Function()? dioFactory;

  Future<TokenRefreshResult>? _inFlight;
  int? _inFlightEpoch;

  /// Resets in-flight refresh state (e.g. on session clear or account switch).
  void reset() {
    _inFlight = null;
    _inFlightEpoch = null;
  }

  /// True when the session now holds a usable access token.
  ///
  /// Single-flight on purpose: a screen with four parallel calls gets four
  /// 401s at once, and four refreshes would race — the last one wins and the
  /// other three tokens are already revoked, signing the user out mid-screen.
  /// They all await the same attempt instead.
  Future<TokenRefreshResult> refresh() {
    final currentEpoch = AuthSession.sessionEpoch;
    final inFlight = _inFlight;
    if (inFlight != null && _inFlightEpoch == currentEpoch) {
      return inFlight;
    }

    final attempt = _refresh(currentEpoch);
    _inFlight = attempt;
    _inFlightEpoch = currentEpoch;
    return attempt.whenComplete(() {
      if (_inFlight == attempt) {
        _inFlight = null;
        _inFlightEpoch = null;
      }
    });
  }

  Future<TokenRefreshResult> _refresh(int requestEpoch) async {
    final refreshToken = AuthSession.tokens?.refreshToken ?? '';
    if (refreshToken.isEmpty || AuthSession.sessionEpoch != requestEpoch) {
      log('no refresh token to trade or session changed', name: 'AuthTokenRefresher');
      return AuthSession.sessionEpoch != requestEpoch
          ? TokenRefreshResult.stale
          : TokenRefreshResult.invalidToken;
    }

    // Logged by hand rather than through the shared `Logger` interceptor: the
    // request body *is* the refresh token, and the interceptor prints bodies.
    log('access token rejected, refreshing…', name: 'AuthTokenRefresher');

    try {
      final dio = dioFactory?.call() ??
          Dio(
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

      if (AuthSession.sessionEpoch != requestEpoch || !AuthSession.isSignedIn) {
        log('refresh completed but session epoch changed or signed out; ignoring', name: 'AuthTokenRefresher');
        return TokenRefreshResult.stale;
      }

      final body = response.data;
      final data = body is Map ? body : null;
      if (data is! Map) {
        log('refresh response had no data block', name: 'AuthTokenRefresher');
        return TokenRefreshResult.networkError;
      }

      final refreshed = LoginResponse.fromJson(Map<String, dynamic>.from(data));
      if (!refreshed.hasTokens) {
        log('refresh response missing token fields', name: 'AuthTokenRefresher');
        return TokenRefreshResult.networkError;
      }

      if (AuthSession.sessionEpoch != requestEpoch || !AuthSession.isSignedIn) {
        return TokenRefreshResult.stale;
      }

      // The server rotates the refresh token too, so the whole pair is
      // replaced — keeping the old one would fail the next refresh.
      AuthSession.updateTokens(refreshed);
      log(
        'refreshed successfully',
        name: 'AuthTokenRefresher',
      );
      return TokenRefreshResult.success;
    } on DioException catch (error) {
      log('refresh dio error: $error', name: 'AuthTokenRefresher');
      if (AuthSession.sessionEpoch != requestEpoch || !AuthSession.isSignedIn) {
        return TokenRefreshResult.stale;
      }
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        if (statusCode == 401) {
          return TokenRefreshResult.invalidToken;
        }
        return TokenRefreshResult.networkError;
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.cancel:
        case DioExceptionType.badCertificate:
        case DioExceptionType.badResponse:
        case DioExceptionType.unknown:
        default:
          return TokenRefreshResult.networkError;
      }
    } catch (error) {
      log('refresh failed: $error', name: 'AuthTokenRefresher');
      if (AuthSession.sessionEpoch != requestEpoch || !AuthSession.isSignedIn) {
        return TokenRefreshResult.stale;
      }
      return TokenRefreshResult.networkError;
    }
  }
}
