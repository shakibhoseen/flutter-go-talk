import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../feature/chat_inbox/data/chat_seen_ack_manager.dart';
import '../../feature/chat_inbox/data/outbox/chat_outbox_processor.dart';
import '../../feature/login/model/login_response.dart';
import '../db/local_cache/cache_manager.dart';
import '../db/local_cache/chat_message_cache.dart';
import '../db/network/dio/auth_dio.dart';
import '../db/network/dio/dio.dart';
import 'auth_session_store.dart';
import 'auth_token_refresher.dart';

/// The signed-in session for this run.
///
/// Kept in memory for the run and on disk between runs (see
/// [AuthSessionStore]); [AuthBootstrap.restoreSession] brings it back at
/// startup. Every reader goes through this class, so persistence is the only
/// thing that had to know where the tokens live.
final class AuthSession {
  AuthSession._();

  static int _sessionEpoch = 0;
  static int get sessionEpoch => _sessionEpoch;

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

  static Future<void>? _pendingClearFuture;

  /// Returns a Future that completes when the current session clear and cache wipe finishes.
  static Future<void> get pendingClearFuture =>
      _pendingClearFuture ?? Future.value();

  /// Takes a fresh login, points the client at it, bumps session epoch, and stores it.
  static void start(LoginResponse response) {
    final expiry = DateTime.now().add(const Duration(minutes: 30));
    adopt(response, accessExpiresAt: expiry);
    final currentEpoch = _sessionEpoch;
    // Not awaited: a disk write must not sit between the user tapping Log in
    // and the app reacting. Coordinated with pendingClearFuture so a logout in flight
    // does not clear the new session store.
    unawaited(
      pendingClearFuture.then(
        (_) => AuthSessionStore.write(response, expiry, epoch: currentEpoch),
      ),
    );
  }

  /// Updates tokens for an existing session (e.g. after refresh) without bumping session epoch.
  static void updateTokens(LoginResponse response) {
    final expiry = DateTime.now().add(const Duration(minutes: 30));
    _applySession(response, expiry);
    final currentEpoch = _sessionEpoch;
    unawaited(
      pendingClearFuture.then(
        (_) => AuthSessionStore.write(response, expiry, epoch: currentEpoch),
      ),
    );
  }

  /// Installs a session without writing it back — for the one that just came
  /// *off* disk at startup, or when adopting a new session in-memory.
  static void adopt(LoginResponse response, {DateTime? accessExpiresAt}) {
    _sessionEpoch++;
    _applySession(
      response,
      accessExpiresAt ?? DateTime.now().add(const Duration(minutes: 30)),
    );
  }

  /// Diagnostic property reporting whether the last disk store clear succeeded.
  static bool? get lastStoreClearSuccess => AuthSessionStore.lastClearSuccess;

  static void _applySession(LoginResponse response, DateTime expiry) {
    _tokens = response;
    _accessTokenExpiry = expiry;
    AuthDioSingleton.instance.update(response.token);
    // `DioSingleton` (`GlobalDataApi`) is this app's general/chat client —
    // one backend, one bearer, unlike the multi-service split this app was
    // templated from where each service had its own separate auth.
    DioSingleton.instance.update(response.token);
    signedIn.value = true;
  }

  /// Atomically clears the session ONLY IF the current epoch matches [expectedEpoch].
  /// Returns `true` if this call actually transitioned the session from signed-in to cleared.
  /// Returns `false` if the session was already cleared or belongs to a different epoch.
  static Future<bool> clearIfEpochMatches(int expectedEpoch) async {
    if (_sessionEpoch != expectedEpoch || !isSignedIn) {
      return false;
    }
    await clear();
    return true;
  }

  static Future<void> clear() {
    _sessionEpoch++;
    _tokens = null;
    _accessTokenExpiry = null;
    AuthDioSingleton.instance.update(null);
    DioSingleton.instance.update(null);
    signedIn.value = false;
    AuthTokenRefresher.instance.reset();
    ChatOutboxProcessor.instance.cancel();
    ChatSeenAckManager.instance.reset();
    final storeClear = AuthSessionStore.clear();
    final cacheClear = CacheManager().clearAllCache();
    final messageCacheClear = ChatMessageCache().clearAll();
    final clearFuture = Future.wait([storeClear, cacheClear, messageCacheClear]);
    _pendingClearFuture = clearFuture;
    return clearFuture;
  }
}
