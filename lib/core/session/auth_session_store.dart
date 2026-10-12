import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../feature/login/model/login_response.dart';
import 'auth_session.dart';

/// The session on disk, so closing the app does not sign the user out.
///
/// Plain [SharedPreferences]: the refresh token is a bearer credential, not a
/// password, it is scoped to this install's device id and the server can
/// revoke it. If the security review later asks for the keychain/keystore,
/// only this file changes.
final class AuthSessionStore {
  AuthSessionStore._();

  static const String _tokensKey = 'auth_session_tokens';
  static const String _expiryKey = 'auth_access_expires_at';

  static SharedPreferences? _prefs;

  /// Serialized FIFO execution chain for all disk mutations.
  static Future<void> _ioQueue = Future.value();

  static bool? _lastClearSuccess;

  /// Observable diagnostic reporting whether the last session clear operation
  /// succeeded in removing (or invalidating) persisted credentials from disk.
  static bool? get lastClearSuccess => _lastClearSuccess;

  @visibleForTesting
  static void setMockPreferences(SharedPreferences? prefs) {
    _prefs = prefs;
  }

  @visibleForTesting
  static void resetForTesting() {
    _prefs = null;
    _ioQueue = Future.value();
    _lastClearSuccess = null;
  }

  /// Must run before [read]. Called once during startup.
  static Future<void> ensureReady() async {
    if (_prefs != null) return;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (error) {
      log('preferences unavailable: $error', name: 'AuthSessionStore');
    }
  }

  static Future<T> _enqueue<T>(
    Future<T> Function() operation, {
    required T fallback,
  }) {
    final completer = Completer<T>();
    _ioQueue = _ioQueue.then((_) async {
      await ensureReady();
      try {
        final result = await operation();
        completer.complete(result);
      } catch (error, stackTrace) {
        log(
          'persistence error: $error',
          name: 'AuthSessionStore',
          error: error,
          stackTrace: stackTrace,
        );
        completer.complete(fallback);
      }
    }, onError: (Object error) {
      log('queue chaining error: $error', name: 'AuthSessionStore');
      if (!completer.isCompleted) {
        completer.complete(fallback);
      }
    });
    return completer.future;
  }

  /// The stored session, or null when there is none (or it cannot be read —
  /// a corrupt entry signs the user out rather than crashing startup).
  static ({LoginResponse tokens, DateTime? accessExpiresAt})? read() {
    final raw = _prefs?.getString(_tokensKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final tokens = LoginResponse.fromJson(Map<String, dynamic>.from(decoded));
      if (!(tokens.token?.isNotEmpty ?? false)) return null;

      final expiryRaw = _prefs?.getString(_expiryKey);
      return (
        tokens: tokens,
        accessExpiresAt: expiryRaw == null
            ? null
            : DateTime.tryParse(expiryRaw),
      );
    } catch (error) {
      log('could not read stored session: $error', name: 'AuthSessionStore');
      return null;
    }
  }

  static Future<bool> write(
    LoginResponse tokens,
    DateTime accessExpiresAt, {
    int? epoch,
  }) {
    return _enqueue<bool>(() async {
      final prefs = _prefs;
      if (prefs == null) return false;
      if (epoch != null && epoch != AuthSession.sessionEpoch) {
        log(
          'stale write cancelled: epoch $epoch != current ${AuthSession.sessionEpoch}',
          name: 'AuthSessionStore',
        );
        return false;
      }
      try {
        final tOk = await prefs.setString(_tokensKey, jsonEncode(tokens.toJson()));
        final eOk = await prefs.setString(_expiryKey, accessExpiresAt.toIso8601String());
        return tOk && eOk;
      } catch (error) {
        log('could not store session: $error', name: 'AuthSessionStore');
        return false;
      }
    }, fallback: false);
  }

  static Future<bool> _clearKeyWithRetry(
    SharedPreferences prefs,
    String key, {
    int maxAttempts = 2,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final removed = await prefs.remove(key);
        if (removed) {
          return true;
        }
        log(
          'prefs.remove($key) returned false on attempt $attempt/$maxAttempts',
          name: 'AuthSessionStore',
        );
      } catch (error) {
        log(
          'prefs.remove($key) threw on attempt $attempt/$maxAttempts: $error',
          name: 'AuthSessionStore',
        );
      }
    }

    // Best-effort fallback overwrite if removal fails.
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final overwritten = await prefs.setString(key, '');
        if (overwritten) {
          log(
            'prefs.remove($key) failed, fallback overwrite succeeded',
            name: 'AuthSessionStore',
          );
          return true;
        }
        log(
          'fallback prefs.setString($key, "") returned false on attempt $attempt/$maxAttempts',
          name: 'AuthSessionStore',
        );
      } catch (error) {
        log(
          'fallback prefs.setString($key, "") threw on attempt $attempt/$maxAttempts: $error',
          name: 'AuthSessionStore',
        );
      }
    }

    return false;
  }

  static Future<bool> clear() {
    return _enqueue<bool>(() async {
      final prefs = _prefs;
      if (prefs == null) {
        log('could not clear stored session: preferences is null', name: 'AuthSessionStore');
        _lastClearSuccess = false;
        return false;
      }

      final tokensCleared = await _clearKeyWithRetry(prefs, _tokensKey);
      final expiryCleared = await _clearKeyWithRetry(prefs, _expiryKey);

      final success = tokensCleared && expiryCleared;
      _lastClearSuccess = success;
      if (!success) {
        log(
          'clear() incomplete: tokensCleared=$tokensCleared, expiryCleared=$expiryCleared',
          name: 'AuthSessionStore',
        );
      }
      return success;
    }, fallback: false);
  }
}
