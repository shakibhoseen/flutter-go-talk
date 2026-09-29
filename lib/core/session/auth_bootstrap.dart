import 'dart:async';

import 'auth_session.dart';
import 'auth_session_store.dart';
import 'auth_token_refresher.dart';

/// Brings a stored session back at startup.
final class AuthBootstrap {
  AuthBootstrap._();

  /// Reads the saved tokens back into [AuthSession], and renews the access
  /// token in the background when it has already expired.
  ///
  /// Only the disk read is awaited — that is what the first frame needs to
  /// know whether this is a signed-in user or a guest. The renewal is not:
  /// the access token lives fifteen minutes, so almost every cold start would
  /// otherwise sit on a network round trip behind the splash. Anything that
  /// races ahead of the renewal simply gets a 401 and is retried by
  /// `AuthRefreshInterceptor`, which shares this same single-flight refresh.
  ///
  /// A refresh token the server has already retired ends as a clean guest
  /// state rather than a session that fails on its first call.
  static Future<void> restoreSession() async {
    await AuthSessionStore.ensureReady();
    final stored = AuthSessionStore.read();
    if (stored == null) {
      return;
    }

    AuthSession.adopt(stored.tokens, accessExpiresAt: stored.accessExpiresAt);
    if (!AuthSession.isAccessTokenExpired) {
      return;
    }

    unawaited(
      AuthTokenRefresher.instance.refresh().then((renewed) {
        if (!renewed) {
          AuthSession.clear();
        }
      }),
    );
  }
}
