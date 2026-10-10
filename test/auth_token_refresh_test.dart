import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_flutter_go/core/db/network/dio/auth_refresh_interceptor.dart';
import 'package:whatsapp_flutter_go/core/session/auth_bootstrap.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session_store.dart';
import 'package:whatsapp_flutter_go/core/session/auth_token_refresher.dart';
import 'package:whatsapp_flutter_go/feature/login/model/login_response.dart';

class TestErrorHandler extends ErrorInterceptorHandler {
  DioException? capturedError;
  Response? capturedResponse;

  @override
  void next(DioException err) {
    capturedError = err;
  }

  @override
  void resolve(Response response) {
    capturedResponse = response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthSessionStore.ensureReady();
    await AuthSession.clear();
    AuthTokenRefresher.dioFactory = null;
  });

  tearDown(() async {
    await AuthSession.clear();
    AuthTokenRefresher.dioFactory = null;
  });

  group('P0: AuthTokenRefresher Offline vs Invalid Token Differentiation', () {
    test('1. Network timeout or connection error returns TokenRefreshResult.networkError and does not clear session', () async {
      AuthSession.start(
        LoginResponse(
          token: 'expired_access_token',
          refreshToken: 'valid_refresh_token',
          user: User(id: 42, name: 'Offline User'),
        ),
      );

      // Simulate network connection failure on /auth/refresh
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                  error: 'No internet connection',
                ),
              );
            },
          ),
        );

      final result = await AuthTokenRefresher.instance.refresh();
      expect(result, equals(TokenRefreshResult.networkError));
      // Session must remain intact!
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(42));
    });

    test('2. Definite 401 Unauthorized returns TokenRefreshResult.invalidToken', () async {
      AuthSession.start(
        LoginResponse(
          token: 'expired_access_token',
          refreshToken: 'revoked_refresh_token',
          user: User(id: 42, name: 'Revoked User'),
        ),
      );

      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 401,
                    data: {'error': 'Invalid refresh token'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      final result = await AuthTokenRefresher.instance.refresh();
      expect(result, equals(TokenRefreshResult.invalidToken));
    });

    test('3. Successful refresh returns TokenRefreshResult.success and updates AuthSession', () async {
      AuthSession.start(
        LoginResponse(
          token: 'old_access_token',
          refreshToken: 'old_refresh_token',
          user: User(id: 42, name: 'User'),
        ),
      );

      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'token': 'new_access_token_123',
                    'refresh_token': 'new_refresh_token_456',
                    'user': {'id': 42, 'name': 'User'},
                  },
                ),
              );
            },
          ),
        );

      final result = await AuthTokenRefresher.instance.refresh();
      expect(result, equals(TokenRefreshResult.success));
      expect(AuthSession.accessToken, equals('new_access_token_123'));
      expect(AuthSession.tokens?.refreshToken, equals('new_refresh_token_456'));
      await pumpEventQueue();
    });

    test('4. HTTP 400 Bad Request returns TokenRefreshResult.networkError and does not clear session', () async {
      AuthSession.start(
        LoginResponse(
          token: 'expired_access_token',
          refreshToken: 'some_refresh_token',
          user: User(id: 42, name: 'Active User'),
        ),
      );

      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 400,
                    data: 'Invalid JSON body',
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      final result = await AuthTokenRefresher.instance.refresh();
      expect(result, equals(TokenRefreshResult.networkError));
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(42));
    });

    test('5. HTTP 403 Forbidden returns TokenRefreshResult.networkError and does not clear session', () async {
      AuthSession.start(
        LoginResponse(
          token: 'expired_access_token',
          refreshToken: 'some_refresh_token',
          user: User(id: 42, name: 'Active User'),
        ),
      );

      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 403,
                    data: 'Forbidden',
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      final result = await AuthTokenRefresher.instance.refresh();
      expect(result, equals(TokenRefreshResult.networkError));
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(42));
    });

    test('6. HTTP 200 with non-map body returns TokenRefreshResult.networkError and does not clear session', () async {
      AuthSession.start(
        LoginResponse(
          token: 'expired_access_token',
          refreshToken: 'some_refresh_token',
          user: User(id: 42, name: 'Active User'),
        ),
      );

      // Simulate 200 OK with non-map / HTML error body (e.g. captive portal or proxy)
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: '<html>Captive Portal</html>',
                ),
              );
            },
          ),
        );

      final result = await AuthTokenRefresher.instance.refresh();
      expect(result, equals(TokenRefreshResult.networkError));
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(42));
    });

    test('7. HTTP 200 with missing token fields returns TokenRefreshResult.networkError and does not clear session', () async {
      AuthSession.start(
        LoginResponse(
          token: 'expired_access_token',
          refreshToken: 'some_refresh_token',
          user: User(id: 42, name: 'Active User'),
        ),
      );

      // Simulate 200 OK with map but missing token fields
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'user': {'id': 42, 'name': 'User'}},
                ),
              );
            },
          ),
        );

      final result = await AuthTokenRefresher.instance.refresh();
      expect(result, equals(TokenRefreshResult.networkError));
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(42));
    });

    test('8. HTTP 200 with JSON parsing exception returns TokenRefreshResult.networkError and does not clear session', () async {
      AuthSession.start(
        LoginResponse(
          token: 'expired_access_token',
          refreshToken: 'some_refresh_token',
          user: User(id: 42, name: 'Active User'),
        ),
      );

      // Simulate 200 OK with unexpected types causing a TypeError during parsing
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'access_token': 12345, 'refresh_token': 67890},
                ),
              );
            },
          ),
        );

      final result = await AuthTokenRefresher.instance.refresh();
      expect(result, equals(TokenRefreshResult.networkError));
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(42));
    });
  });

  group('P0: AuthBootstrap Offline Cold Start', () {
    test('1. Expired token on cold start when offline does NOT clear AuthSession', () async {
      final initialTokens = LoginResponse(
        token: 'expired_jwt',
        refreshToken: 'stored_refresh_token',
        user: User(id: 99, name: 'Persistent User'),
      );
      final expiredDate = DateTime.now().subtract(const Duration(hours: 1));
      await AuthSessionStore.write(initialTokens, expiredDate);

      // Offline network
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                  error: 'Connection timed out',
                ),
              );
            },
          ),
        );

      await AuthBootstrap.restoreSession();
      // Allow background refresher to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // User must remain signed in so cached data is accessible offline
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(99));
      expect(AuthSession.isAccessTokenExpired, isTrue);
      // AuthSessionStore must not have been erased
      final stored = AuthSessionStore.read();
      expect(stored, isNotNull);
      expect(stored!.tokens.token, equals('expired_jwt'));
    });

    test('2. Expired token on cold start with definite invalid-token rejection clears AuthSession', () async {
      final initialTokens = LoginResponse(
        token: 'expired_jwt',
        refreshToken: 'revoked_refresh_token',
        user: User(id: 99, name: 'Revoked User'),
      );
      final expiredDate = DateTime.now().subtract(const Duration(hours: 1));
      await AuthSessionStore.write(initialTokens, expiredDate);

      // Server rejects refresh
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 401,
                    data: {'error': 'Refresh token expired or invalid'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      await AuthBootstrap.restoreSession();
      // Allow background refresher to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Definite invalid token rejection must wipe the session
      expect(AuthSession.isSignedIn, isFalse);
      expect(AuthSession.tokens, isNull);
    });

    test('3. Expired token on cold start with 400 or 403 response does NOT clear AuthSession', () async {
      final initialTokens = LoginResponse(
        token: 'expired_jwt',
        refreshToken: 'stored_refresh_token',
        user: User(id: 99, name: 'Persistent User'),
      );
      final expiredDate = DateTime.now().subtract(const Duration(hours: 1));
      await AuthSessionStore.write(initialTokens, expiredDate);

      // Server returns 400 Bad Request
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 400,
                    data: 'Invalid JSON body',
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      await AuthBootstrap.restoreSession();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Session must remain intact
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(99));
      expect(AuthSessionStore.read()?.tokens.token, equals('expired_jwt'));
    });

    test('4. Unexpected asynchronous error during background refresh is safely caught and does not clear session', () async {
      final initialTokens = LoginResponse(
        token: 'expired_jwt',
        refreshToken: 'stored_refresh_token',
        user: User(id: 99, name: 'Persistent User'),
      );
      final expiredDate = DateTime.now().subtract(const Duration(hours: 1));
      await AuthSessionStore.write(initialTokens, expiredDate);

      // Simulate unexpected thrown error
      AuthTokenRefresher.dioFactory = () => throw Exception('Unexpected factory failure');

      await AuthBootstrap.restoreSession();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(99));
    });
  });

  group('P0: AuthRefreshInterceptor Offline vs Invalid Token', () {
    test('1. 401 with network error during refresh forwards error without clearing session', () async {
      AuthSession.start(
        LoginResponse(
          token: 'token',
          refreshToken: 'refresh_token',
          user: User(id: 7, name: 'User 7'),
        ),
      );

      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                ),
              );
            },
          ),
        );

      var sessionExpiredCalled = false;
      final interceptor = AuthRefreshInterceptor(
        dioProvider: () => Dio(),
        onSessionExpired: () => sessionExpiredCalled = true,
      );

      final handler = TestErrorHandler();
      await interceptor.onError(
        DioException(
          requestOptions: RequestOptions(path: '/conversations'),
          response: Response(
            requestOptions: RequestOptions(path: '/conversations'),
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
        handler,
      );

      expect(handler.capturedError, isNotNull);
      expect(sessionExpiredCalled, isFalse);
      expect(AuthSession.isSignedIn, isTrue);
    });

    test('2. 401 with invalid refresh token clears session and invokes onSessionExpired', () async {
      AuthSession.start(
        LoginResponse(
          token: 'token',
          refreshToken: 'bad_refresh_token',
          user: User(id: 7, name: 'User 7'),
        ),
      );

      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 401,
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      var sessionExpiredCalled = false;
      final interceptor = AuthRefreshInterceptor(
        dioProvider: () => Dio(),
        onSessionExpired: () => sessionExpiredCalled = true,
      );

      final handler = TestErrorHandler();
      await interceptor.onError(
        DioException(
          requestOptions: RequestOptions(path: '/conversations'),
          response: Response(
            requestOptions: RequestOptions(path: '/conversations'),
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
        handler,
      );

      expect(handler.capturedError, isNotNull);
      expect(sessionExpiredCalled, isTrue);
      expect(AuthSession.isSignedIn, isFalse);
    });

    test('3. Concurrent refresh calls are deduplicated into a single network attempt', () async {
      AuthSession.start(
        LoginResponse(
          token: 'initial_access_token',
          refreshToken: 'valid_refresh_token',
          user: User(id: 7, name: 'User 7'),
        ),
      );

      var networkCalls = 0;
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              networkCalls++;
              await Future<void>.delayed(const Duration(milliseconds: 20));
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'access_token': 'deduped_access_token',
                    'refresh_token': 'deduped_refresh_token',
                    'user': {'id': 7, 'name': 'User 7'},
                  },
                ),
              );
            },
          ),
        );

      final results = await Future.wait([
        AuthTokenRefresher.instance.refresh(),
        AuthTokenRefresher.instance.refresh(),
        AuthTokenRefresher.instance.refresh(),
      ]);

      expect(networkCalls, equals(1));
      expect(results, equals([
        TokenRefreshResult.success,
        TokenRefreshResult.success,
        TokenRefreshResult.success,
      ]));
      expect(AuthSession.accessToken, equals('deduped_access_token'));
      expect(AuthSession.tokens?.refreshToken, equals('deduped_refresh_token'));
      await pumpEventQueue();
      // Verify storage persistence as well
      final stored = AuthSessionStore.read();
      expect(stored?.tokens.token, equals('deduped_access_token'));
      expect(stored?.tokens.refreshToken, equals('deduped_refresh_token'));
    });

    test('4. Concurrent 401 requests deduplicate refresh and retry with new bearer token', () async {
      AuthSession.start(
        LoginResponse(
          token: 'expired_access_token',
          refreshToken: 'valid_refresh_token',
          user: User(id: 7, name: 'User 7'),
        ),
      );

      var refreshCalls = 0;
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              refreshCalls++;
              await Future<void>.delayed(const Duration(milliseconds: 20));
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'access_token': 'new_token_999',
                    'refresh_token': 'new_refresh_999',
                    'user': {'id': 7, 'name': 'User 7'},
                  },
                ),
              );
            },
          ),
        );

      final retriedHeaders = <String?>[];
      final mockReplayDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              retriedHeaders.add(options.headers['Authorization'] as String?);
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'result': 'ok'},
                ),
              );
            },
          ),
        );

      final interceptor = AuthRefreshInterceptor(
        dioProvider: () => mockReplayDio,
      );

      final handler1 = TestErrorHandler();
      final handler2 = TestErrorHandler();

      final req1 = interceptor.onError(
        DioException(
          requestOptions: RequestOptions(path: '/endpoint1'),
          response: Response(
            requestOptions: RequestOptions(path: '/endpoint1'),
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
        handler1,
      );

      final req2 = interceptor.onError(
        DioException(
          requestOptions: RequestOptions(path: '/endpoint2'),
          response: Response(
            requestOptions: RequestOptions(path: '/endpoint2'),
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
        handler2,
      );

      await Future.wait([req1, req2]);

      expect(refreshCalls, equals(1));
      expect(retriedHeaders.length, equals(2));
      expect(retriedHeaders, everyElement(equals('Bearer new_token_999')));
      expect(handler1.capturedResponse, isNotNull);
      expect(handler2.capturedResponse, isNotNull);
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.accessToken, equals('new_token_999'));
    });
  });
}
