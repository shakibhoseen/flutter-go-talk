import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_flutter_go/core/db/network/dio/auth_refresh_interceptor.dart';
import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/di/di.dart';
import 'package:whatsapp_flutter_go/core/session/auth_bootstrap.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session_store.dart';
import 'package:whatsapp_flutter_go/core/session/auth_token_refresher.dart';
import 'package:whatsapp_flutter_go/core/session/session_cubit.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_sync_coordinator.dart';
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

class MockSharedPreferences extends Fake implements SharedPreferences {
  final Map<String, Object> storage = {};
  int removeCallCount = 0;
  int setStringCallCount = 0;
  final List<String> removeKeys = [];
  final List<String> setStringKeys = [];

  bool Function(String key)? onRemove;
  bool removeResult = true;
  Exception? removeException;

  bool Function(String key, String value)? onSetString;
  bool setStringResult = true;
  Exception? setStringException;

  @override
  String? getString(String key) => storage[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    setStringCallCount++;
    setStringKeys.add(key);
    if (onSetString != null) {
      return onSetString!(key, value);
    }
    if (setStringException != null) {
      throw setStringException!;
    }
    if (setStringResult) {
      storage[key] = value;
      return true;
    }
    return false;
  }

  @override
  Future<bool> remove(String key) async {
    removeCallCount++;
    removeKeys.add(key);
    if (onRemove != null) {
      return onRemove!(key);
    }
    if (removeException != null) {
      throw removeException!;
    }
    if (removeResult) {
      storage.remove(key);
      return true;
    }
    return false;
  }

  @override
  bool containsKey(String key) => storage.containsKey(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AuthSessionStore.resetForTesting();
    await AuthSessionStore.ensureReady();
    await AuthSession.clear();
    AuthTokenRefresher.dioFactory = null;
    if (!locator.isRegistered<SessionCubit>()) {
      locator.registerSingleton<SessionCubit>(SessionCubit());
    }
  });

  tearDown(() async {
    AuthSessionStore.resetForTesting();
    await AuthSessionStore.ensureReady();
    await AuthSession.clear();
    AuthTokenRefresher.dioFactory = null;
    ChatSyncCoordinator.instance.stop();
    ChatSocketService.instance.disconnect();
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

  group('P0: Auth Race Conditions, Multi-Account & Storage Regression Matrix', () {
    test('1. Logout during in-flight refresh discards response and does NOT resurrect session', () async {
      AuthSession.start(
        LoginResponse(
          token: 'old_access_token',
          refreshToken: 'valid_refresh_token',
          user: User(id: 1, name: 'Alice'),
        ),
      );

      final refreshCompleter = Completer<Response>();
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              final res = await refreshCompleter.future;
              handler.resolve(res);
            },
          ),
        );

      final refreshFuture = AuthTokenRefresher.instance.refresh();

      // User logs out while refresh is still in flight
      await AuthSession.clear();

      // Server returns HTTP 200 with refreshed tokens
      refreshCompleter.complete(
        Response(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          statusCode: 200,
          data: {
            'token': 'resurrected_token',
            'refresh_token': 'resurrected_refresh',
            'user': {'id': 1, 'name': 'Alice'},
          },
        ),
      );

      await refreshFuture;
      await pumpEventQueue();

      // Session MUST NOT be resurrected!
      expect(AuthSession.isSignedIn, isFalse, reason: 'Session was resurrected after logout');
      expect(AuthSession.tokens, isNull);
      expect(AuthSessionStore.read(), isNull);
    });

    test('2. Account switch during in-flight refresh does NOT overwrite or wipe new account session', () async {
      // Alice is logged in
      AuthSession.start(
        LoginResponse(token: 'alice_token', refreshToken: 'alice_refresh', user: User(id: 1, name: 'Alice')),
      );

      final refreshCompleter = Completer<Response>();
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              final res = await refreshCompleter.future;
              handler.resolve(res);
            },
          ),
        );

      final aliceRefreshFuture = AuthTokenRefresher.instance.refresh();

      // Alice logs out and Bob logs in
      await AuthSession.clear();
      AuthSession.start(
        LoginResponse(token: 'bob_token', refreshToken: 'bob_refresh', user: User(id: 2, name: 'Bob')),
      );

      // Alice's refresh completes
      refreshCompleter.complete(
        Response(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          statusCode: 200,
          data: {'token': 'alice_new_token', 'refresh_token': 'alice_new_refresh', 'user': {'id': 1, 'name': 'Alice'}},
        ),
      );

      await aliceRefreshFuture;
      await pumpEventQueue();

      // Bob's session must remain active and unmodified!
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(2), reason: "Bob's user was overwritten by Alice's response");
      expect(AuthSession.tokens?.token, equals('bob_token'));
      final stored = AuthSessionStore.read();
      expect(stored?.tokens.user?.id, equals(2));
      expect(stored?.tokens.token, equals('bob_token'));
    });

    test('3. Stale refresh response does not retry request on new account', () async {
      // Alice is logged in
      AuthSession.start(
        LoginResponse(token: 'alice_token', refreshToken: 'alice_refresh', user: User(id: 1, name: 'Alice')),
      );

      final refreshCompleter = Completer<Response>();
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              final res = await refreshCompleter.future;
              handler.resolve(res);
            },
          ),
        );

      final mockReplayDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 401),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      final interceptor = AuthRefreshInterceptor(dioProvider: () => mockReplayDio);
      final handler = TestErrorHandler();

      // Alice's request gets 401
      final aliceRequest = interceptor.onError(
        DioException(
          requestOptions: RequestOptions(path: '/user/alice_data'),
          response: Response(requestOptions: RequestOptions(path: '/user/alice_data'), statusCode: 401),
          type: DioExceptionType.badResponse,
        ),
        handler,
      );

      // While Alice's refresh is pending, Alice logs out and Bob logs in
      await AuthSession.clear();
      AuthSession.start(
        LoginResponse(token: 'bob_token', refreshToken: 'bob_refresh', user: User(id: 2, name: 'Bob')),
      );

      // Alice's refresh completes
      refreshCompleter.complete(
        Response(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          statusCode: 200,
          data: {'token': 'alice_new_token', 'refresh_token': 'alice_new_refresh'},
        ),
      );

      await aliceRequest;
      await pumpEventQueue();

      // Alice's request must receive error, Bob's session must stay active
      expect(handler.capturedError, isNotNull);
      expect(handler.capturedError?.response?.statusCode, equals(401));
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(2));
    });

    test('4. Concurrent 401s on invalid refresh token: single-flight, single-expiry, and error propagation', () async {
      AuthSession.start(
        LoginResponse(token: 'token', refreshToken: 'bad_refresh', user: User(id: 1, name: 'Alice')),
      );

      var networkAttempts = 0;
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              networkAttempts++;
              await Future<void>.delayed(const Duration(milliseconds: 20));
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 401),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      var expiryCallbackCount = 0;
      final interceptor = AuthRefreshInterceptor(
        dioProvider: () => Dio(),
        onSessionExpired: () => expiryCallbackCount++,
      );

      final handler1 = TestErrorHandler();
      final handler2 = TestErrorHandler();

      final req1 = interceptor.onError(
        DioException(
          requestOptions: RequestOptions(path: '/endpoint1'),
          response: Response(requestOptions: RequestOptions(path: '/endpoint1'), statusCode: 401),
          type: DioExceptionType.badResponse,
        ),
        handler1,
      );

      final req2 = interceptor.onError(
        DioException(
          requestOptions: RequestOptions(path: '/endpoint2'),
          response: Response(requestOptions: RequestOptions(path: '/endpoint2'), statusCode: 401),
          type: DioExceptionType.badResponse,
        ),
        handler2,
      );

      await Future.wait([req1, req2]);

      expect(networkAttempts, equals(1));
      expect(expiryCallbackCount, equals(1), reason: 'Expiry callback must be called exactly once');
      expect(handler1.capturedError?.response?.statusCode, equals(401));
      expect(handler2.capturedError?.response?.statusCode, equals(401));
      expect(AuthSession.isSignedIn, isFalse);
    });

    test('5. Retried request receiving 401 propagates error without attempting another refresh', () async {
      AuthSession.start(
        LoginResponse(token: 'token_1', refreshToken: 'valid_refresh', user: User(id: 1, name: 'Alice')),
      );

      var refreshCount = 0;
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              refreshCount++;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'token': 'new_token', 'refresh_token': 'new_refresh'},
                ),
              );
            },
          ),
        );

      final mockReplayDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 401),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      final interceptor = AuthRefreshInterceptor(dioProvider: () => mockReplayDio);
      final handler = TestErrorHandler();

      await interceptor.onError(
        DioException(
          requestOptions: RequestOptions(path: '/chats'),
          response: Response(requestOptions: RequestOptions(path: '/chats'), statusCode: 401),
          type: DioExceptionType.badResponse,
        ),
        handler,
      );

      expect(refreshCount, equals(1), reason: 'Refresh must not loop for retried request');
      expect(handler.capturedError?.response?.statusCode, equals(401));
    });

    test('6. Network error during refresh keeps session intact (offline safety)', () async {
      AuthSession.start(
        LoginResponse(token: 'token_1', refreshToken: 'valid_refresh', user: User(id: 1, name: 'Alice')),
      );

      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                  error: 'Connection timeout',
                ),
              );
            },
          ),
        );

      var expiryCount = 0;
      final interceptor = AuthRefreshInterceptor(
        dioProvider: () => Dio(),
        onSessionExpired: () => expiryCount++,
      );
      final handler = TestErrorHandler();

      await interceptor.onError(
        DioException(
          requestOptions: RequestOptions(path: '/chats'),
          response: Response(requestOptions: RequestOptions(path: '/chats'), statusCode: 401),
          type: DioExceptionType.badResponse,
        ),
        handler,
      );

      expect(AuthSession.isSignedIn, isTrue);
      expect(expiryCount, equals(0));
      expect(handler.capturedError, isNotNull);
    });

    test('7. Cold-start invalid token updates SessionCubit, stops socket and sync coordinator', () async {
      final sessionCubit = locator<SessionCubit>();
      final initialTokens = LoginResponse(
        token: 'expired_jwt',
        refreshToken: 'revoked_refresh',
        user: User(id: 99, name: 'User 99'),
      );
      final expiredDate = DateTime.now().subtract(const Duration(hours: 1));
      await AuthSessionStore.write(initialTokens, expiredDate);

      // Start socket and coordinator as AppStartup would
      ChatSyncCoordinator.instance.start();
      ChatSocketService.instance.connect();
      expect(ChatSyncCoordinator.instance.isListening, isTrue);

      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 401),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      await AuthBootstrap.restoreSession();
      // AppStartup syncs SessionCubit from disk restore
      sessionCubit.sync(isLoggedIn: AuthSession.isSignedIn, accessToken: AuthSession.accessToken);
      expect(sessionCubit.state.isAuthenticated, isTrue);

      // Wait for background refresh to reject
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(AuthSession.isSignedIn, isFalse);
      expect(sessionCubit.state.isAuthenticated, isFalse, reason: 'SessionCubit remained authenticated on invalid cold-start refresh');
      expect(sessionCubit.state.isGuest, isTrue);
      expect(ChatSyncCoordinator.instance.isListening, isFalse, reason: 'ChatSyncCoordinator was not stopped on cold-start invalid token');
      expect(ChatSocketService.instance.connectionState.value, equals(SocketConnectionState.disconnected));
    });

    test('8. Storage ordering: unawaited write followed by clear does not persist token to disk', () async {
      final tokens = LoginResponse(
        token: 'transient_token',
        refreshToken: 'transient_refresh',
        user: User(id: 77, name: 'Transient User'),
      );

      // Simulate start() triggering unawaited write, followed immediately by clear()
      AuthSession.start(tokens);
      await AuthSession.clear();
      await pumpEventQueue();

      expect(AuthSession.isSignedIn, isFalse);
      expect(AuthSessionStore.read(), isNull, reason: 'Old write was persisted after clear');
    });

    test('9. Stale refresh success cannot overwrite a newer adopted session', () async {
      final aliceTokens = LoginResponse(
        token: 'alice_access_token',
        refreshToken: 'alice_refresh_token',
        user: User(id: 1, name: 'Alice'),
      );
      final expiredDate = DateTime.now().subtract(const Duration(minutes: 10));
      AuthSession.adopt(aliceTokens, accessExpiresAt: expiredDate);
      final aliceEpoch = AuthSession.sessionEpoch;

      final refreshCompleter = Completer<Response>();
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              final res = await refreshCompleter.future;
              handler.resolve(res);
            },
          ),
        );

      final refreshFuture = AuthTokenRefresher.instance.refresh();

      // While Alice's refresh is in-flight, Bob is adopted (e.g. account switch)
      final bobTokens = LoginResponse(
        token: 'bob_access_token',
        refreshToken: 'bob_refresh_token',
        user: User(id: 2, name: 'Bob'),
      );
      AuthSession.adopt(bobTokens);
      expect(AuthSession.sessionEpoch, greaterThan(aliceEpoch));

      // Alice's refresh returns 200 OK with new tokens for Alice
      refreshCompleter.complete(
        Response(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          statusCode: 200,
          data: {
            'token': 'alice_new_access_token',
            'refresh_token': 'alice_new_refresh_token',
            'user': {'id': 1, 'name': 'Alice'},
          },
        ),
      );

      final result = await refreshFuture;
      await pumpEventQueue();

      expect(result, equals(TokenRefreshResult.stale));
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(2));
      expect(AuthSession.tokens?.user?.name, equals('Bob'));
      expect(AuthSession.accessToken, equals('bob_access_token'));
      expect(AuthSession.tokens?.refreshToken, equals('bob_refresh_token'));
    });

    test('10. Stale refresh 401 cannot clear a newer adopted session', () async {
      final sessionCubit = locator<SessionCubit>();
      final aliceTokens = LoginResponse(
        token: 'alice_access_token',
        refreshToken: 'alice_refresh_token',
        user: User(id: 1, name: 'Alice'),
      );
      final expiredDate = DateTime.now().subtract(const Duration(minutes: 10));
      AuthSession.adopt(aliceTokens, accessExpiresAt: expiredDate);
      sessionCubit.sync(isLoggedIn: true, accessToken: 'alice_access_token');
      final aliceEpoch = AuthSession.sessionEpoch;

      final refreshSignal = Completer<void>();
      AuthTokenRefresher.dioFactory = () => Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              await refreshSignal.future;
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 401,
                    data: {'error': 'Revoked refresh token'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

      final refreshFuture = AuthTokenRefresher.instance.refresh();

      // Bob is adopted while refresh is in-flight
      final bobTokens = LoginResponse(
        token: 'bob_access_token',
        refreshToken: 'bob_refresh_token',
        user: User(id: 2, name: 'Bob'),
      );
      AuthSession.adopt(bobTokens);
      sessionCubit.sync(isLoggedIn: true, accessToken: 'bob_access_token');
      expect(AuthSession.sessionEpoch, greaterThan(aliceEpoch));

      // Signal completion so Alice's refresh receives 401 Unauthorized
      refreshSignal.complete();

      final result = await refreshFuture;
      await pumpEventQueue();

      expect(result, equals(TokenRefreshResult.stale));
      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(2));
      expect(AuthSession.tokens?.user?.name, equals('Bob'));
      expect(AuthSession.accessToken, equals('bob_access_token'));
      expect(AuthSession.tokens?.refreshToken, equals('bob_refresh_token'));
      expect(sessionCubit.state.isAuthenticated, isTrue);
      expect(sessionCubit.state.isGuest, isFalse);
    });

    test('11. Storage clear: remove() returning false is handled with bounded retries and fallback overwrite', () async {
      final mockPrefs = MockSharedPreferences();
      mockPrefs.onRemove = (key) => false;
      mockPrefs.onSetString = (key, value) {
        mockPrefs.storage[key] = value;
        return true;
      };
      mockPrefs.storage['auth_session_tokens'] = '{"token":"valid","user":{"id":1,"name":"Alice"}}';
      mockPrefs.storage['auth_access_expires_at'] = DateTime.now().toIso8601String();

      AuthSessionStore.setMockPreferences(mockPrefs);

      final clearSuccess = await AuthSessionStore.clear();

      expect(clearSuccess, isTrue);
      expect(AuthSessionStore.lastClearSuccess, isTrue);
      expect(AuthSession.lastStoreClearSuccess, isTrue);
      expect(mockPrefs.removeCallCount, equals(4)); // 2 attempts * 2 keys
      expect(mockPrefs.setStringCallCount, equals(2)); // fallback overwrite
      expect(mockPrefs.storage['auth_session_tokens'], equals(''));
      expect(mockPrefs.storage['auth_access_expires_at'], equals(''));
      expect(AuthSessionStore.read(), isNull);
    });

    test('12. Storage clear: remove() throwing exception is safely caught and falls back without crashing', () async {
      final mockPrefs = MockSharedPreferences();
      mockPrefs.onRemove = (key) => throw Exception('Disk I/O error');
      mockPrefs.onSetString = (key, value) {
        mockPrefs.storage[key] = value;
        return true;
      };
      mockPrefs.storage['auth_session_tokens'] = '{"token":"valid","user":{"id":1,"name":"Alice"}}';
      mockPrefs.storage['auth_access_expires_at'] = DateTime.now().toIso8601String();

      AuthSessionStore.setMockPreferences(mockPrefs);

      await expectLater(AuthSession.clear(), completes);

      expect(AuthSessionStore.lastClearSuccess, isTrue);
      expect(AuthSession.lastStoreClearSuccess, isTrue);
      expect(AuthSession.isSignedIn, isFalse);
      expect(mockPrefs.removeCallCount, equals(4));
      expect(mockPrefs.setStringCallCount, equals(2));
      expect(AuthSessionStore.read(), isNull);
    });

    test('13. Storage clear: failure clearing one key does not prevent attempting to clear the other key', () async {
      final mockPrefs = MockSharedPreferences();
      mockPrefs.onRemove = (key) {
        if (key == 'auth_session_tokens') return false;
        mockPrefs.storage.remove(key);
        return true;
      };
      mockPrefs.onSetString = (key, value) {
        if (key == 'auth_session_tokens') throw Exception('Write failed');
        mockPrefs.storage[key] = value;
        return true;
      };
      mockPrefs.storage['auth_session_tokens'] = '{"token":"valid","user":{"id":1,"name":"Alice"}}';
      mockPrefs.storage['auth_access_expires_at'] = DateTime.now().toIso8601String();

      AuthSessionStore.setMockPreferences(mockPrefs);

      final clearSuccess = await AuthSessionStore.clear();

      expect(clearSuccess, isFalse);
      expect(AuthSessionStore.lastClearSuccess, isFalse);
      expect(AuthSession.lastStoreClearSuccess, isFalse);
      expect(mockPrefs.removeKeys, containsAll(['auth_session_tokens', 'auth_access_expires_at']));
      expect(mockPrefs.storage.containsKey('auth_access_expires_at'), isFalse);
    });

    test('14. Storage queue: subsequent queued storage operations still execute after a failed clear', () async {
      final mockPrefs = MockSharedPreferences();
      mockPrefs.onRemove = (key) => false;
      mockPrefs.onSetString = (key, value) {
        // Fallback overwrite during clear writes empty string
        if (value.isEmpty) return false;
        mockPrefs.storage[key] = value;
        return true;
      };

      AuthSessionStore.setMockPreferences(mockPrefs);

      // Enqueue clear() which fails
      final clearFuture = AuthSessionStore.clear();

      // Immediately enqueue write() behind the clear()
      final bobTokens = LoginResponse(
        token: 'bob_token',
        refreshToken: 'bob_refresh',
        user: User(id: 2, name: 'Bob'),
      );
      final bobExpiry = DateTime.now().add(const Duration(minutes: 30));
      final writeFuture = AuthSessionStore.write(bobTokens, bobExpiry);

      final clearSuccess = await clearFuture;
      final writeSuccess = await writeFuture;

      expect(clearSuccess, isFalse);
      expect(writeSuccess, isTrue, reason: 'Queue did not block or drop subsequent write after failed clear');
      expect(AuthSessionStore.read()?.tokens.user?.id, equals(2));
      expect(AuthSessionStore.read()?.tokens.token, equals('bob_token'));
    });

    test('15. Cold start restore behavior when credentials remain persisted after a failed clear', () async {
      final mockPrefs = MockSharedPreferences();
      final persistedAlice = LoginResponse(
        token: 'persisted_alice_token',
        refreshToken: 'persisted_alice_refresh',
        user: User(id: 1, name: 'Alice'),
      );
      mockPrefs.storage['auth_session_tokens'] = jsonEncode(persistedAlice.toJson());
      mockPrefs.storage['auth_access_expires_at'] = DateTime.now().add(const Duration(hours: 1)).toIso8601String();

      AuthSessionStore.setMockPreferences(mockPrefs);

      await AuthBootstrap.restoreSession();

      expect(AuthSession.isSignedIn, isTrue);
      expect(AuthSession.tokens?.user?.id, equals(1));
      expect(AuthSession.tokens?.user?.name, equals('Alice'));
      expect(AuthSession.accessToken, equals('persisted_alice_token'));
      expect(AuthSession.tokens?.refreshToken, equals('persisted_alice_refresh'));
    });

    test('16. Storage clear: fallback write false return or exception is treated as failure (lastClearSuccess == false)', () async {
      final mockPrefs = MockSharedPreferences();
      mockPrefs.onRemove = (key) => false;
      mockPrefs.onSetString = (key, value) => throw Exception('Disk full');

      AuthSessionStore.setMockPreferences(mockPrefs);

      final clearSuccess = await AuthSessionStore.clear();

      expect(clearSuccess, isFalse, reason: 'Failed fallback write must not be reported as success');
      expect(AuthSessionStore.lastClearSuccess, isFalse);
      expect(AuthSession.lastStoreClearSuccess, isFalse);

      await expectLater(AuthSession.clear(), completes);
      expect(AuthSession.isSignedIn, isFalse);
    });
  });
}
