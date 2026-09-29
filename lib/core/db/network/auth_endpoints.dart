/// Paths on the accounts service (see [NetworkServiceType.auth]). Kept apart
/// from [Endpoints] because they resolve against a different base url.
final class AuthEndpoints {
  AuthEndpoints._();

  /// The OAuth-style client this build identifies itself as. The accounts
  /// service issues tokens per client, so a wrong value fails the login rather
  /// than logging in as something else.
  static const String clientId = 'packly-customer-android';

  static String login() => 'auth/login';
  static String register() => 'auth/register';

  /// Trades a refresh token for a new access token. Takes no bearer — the
  /// refresh token in the body *is* the credential.
  static String refresh() => 'api/v1/auth/refresh';

  /// Ends the session the bearer belongs to. Body-less.
  static String logout() => 'api/v1/auth/logout';

  /// The signed-in account. Doubles as the access token's validity check:
  /// 401 `TOKEN_INVALID` is the server saying "refresh first".
  static String me() => 'api/v1/auth/me';
}
