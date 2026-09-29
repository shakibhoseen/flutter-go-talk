import 'dart:async';

import '../navigation/navigation_service.dart';
import '../navigation/routes/auth_routes.dart';
import 'auth_session.dart';

/// One place for "this needs a signed-in user".
///
/// Browsing is open to guests, so the check belongs at the actions that
/// genuinely need an account (profile, checkout, wishlist) rather than at the
/// app's entry — and it belongs here rather than in each of them, so the
/// answer to "what happens when a guest taps this" is written once.
final class AuthGate {
  AuthGate._();

  /// True when the caller may proceed — already signed in, or signed in just
  /// now on the login screen this opened.
  ///
  /// A guest never lands on the gated destination first: the login screen is
  /// pushed over whatever they were on, and cancelling it leaves them exactly
  /// there.
  static Future<bool> ensureSignedIn() async {
    if (AuthSession.isSignedIn) {
      return true;
    }
    await _openLogin();
    return AuthSession.isSignedIn;
  }

  /// The session died mid-use: the access token was rejected and the refresh
  /// token could not replace it. Nothing is retried after this — the user has
  /// to sign in again before the call that failed can mean anything.
  static void handleSessionExpired() {
    AuthSession.clear();
    unawaited(_openLogin());
  }

  static bool _loginIsOpen = false;

  /// Guarded because several failing calls can ask at once — without this the
  /// user gets a stack of login screens and has to dismiss them one by one.
  static Future<void> _openLogin() async {
    if (_loginIsOpen) return;
    _loginIsOpen = true;
    try {
      await NavigationService.navigateTo(AuthRoutes.login);
    } finally {
      _loginIsOpen = false;
    }
  }
}
