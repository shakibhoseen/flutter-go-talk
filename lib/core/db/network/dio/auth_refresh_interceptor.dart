import 'package:dio/dio.dart';

import '../../../session/auth_session.dart';
import '../../../session/auth_token_refresher.dart';
import '../auth_endpoints.dart';

/// Turns a 401 into one refresh-and-retry, and a failed refresh into a
/// sign-out.
///
/// The app never checks token validity up front: the access token lives 15
/// minutes, so a check would be one more round trip that can itself go stale
/// between the check and the call. The 401 *is* the check.
class AuthRefreshInterceptor extends Interceptor {
  AuthRefreshInterceptor({required this.dioProvider, this.onSessionExpired});

  /// Marks a request this interceptor has already retried, so a second 401 on
  /// the same call ends as an error instead of looping.
  static const String _retriedKey = 'auth.refresh_retried';

  /// Calls that must never trigger a refresh: they are how a session is
  /// created or ended in the first place, and their 401 is a real answer
  /// ("wrong password", "this refresh token is spent").
  static const Set<String> _exemptPaths = {'login', 'refresh', 'logout'};

  /// The client to replay the original request on. A function, not a [Dio]:
  /// attaching a token rebuilds the client, so a captured instance would be
  /// the previous one — the retry would go out with the old header.
  final Dio Function() dioProvider;

  /// Called when the refresh failed and the session was cleared, so the UI can
  /// send the user to the login screen.
  final void Function()? onSessionExpired;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 ||
        _isExempt(options.path) ||
        options.extra[_retriedKey] == true ||
        !AuthSession.isSignedIn) {
      handler.next(err);
      return;
    }

    final refreshed = await AuthTokenRefresher.instance.refresh();
    if (!refreshed) {
      AuthSession.clear();
      onSessionExpired?.call();
      handler.next(err);
      return;
    }

    try {
      final response = await dioProvider().fetch<dynamic>(
        options
          ..extra[_retriedKey] = true
          // The client's own default headers were fixed when the request was
          // built, so the retry has to carry the new token itself.
          ..headers['Authorization'] = 'Bearer ${AuthSession.accessToken}',
      );
      handler.resolve(response);
    } on DioException catch (error) {
      handler.next(error);
    }
  }

  bool _isExempt(String path) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return normalized == AuthEndpoints.login() ||
        normalized == AuthEndpoints.refresh() ||
        normalized == AuthEndpoints.logout() ||
        _exemptPaths.contains(normalized.split('/').last);
  }
}
