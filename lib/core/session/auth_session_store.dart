import 'dart:convert';
import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

import '../../feature/login/model/login_response.dart';

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

  /// Must run before [read]. Called once during startup.
  static Future<void> ensureReady() async {
    if (_prefs != null) return;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (error) {
      log('preferences unavailable: $error', name: 'AuthSessionStore');
    }
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
      if (!(tokens.token?.isNotEmpty??false)) return null;

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

  static Future<void> write(
    LoginResponse tokens,
    DateTime accessExpiresAt,
  ) async {
    await ensureReady();
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString(_tokensKey, jsonEncode(tokens.toJson()));
      await prefs.setString(_expiryKey, accessExpiresAt.toIso8601String());
    } catch (error) {
      log('could not store session: $error', name: 'AuthSessionStore');
    }
  }

  static Future<void> clear() async {
    await ensureReady();
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.remove(_tokensKey);
      await prefs.remove(_expiryKey);
    } catch (error) {
      log('could not clear stored session: $error', name: 'AuthSessionStore');
    }
  }
}
