import 'package:dio/dio.dart';

import '../../../session/auth_gate.dart';
import '../exception_handler/data_source.dart';
import '../network_service_type.dart';
import 'app_dio_client.dart';
import 'auth_refresh_interceptor.dart';
import 'request_cancel_scope.dart';

/// The accounts service client.
///
/// Deliberately its own singleton rather than a mode of [DioSingleton]: the
/// accounts host, its bearer token and its error envelope are all separate
/// from the shop's, and mixing them means one service's token refresh can
/// silently rewrite the other's headers.
final class AuthDioSingleton {
  AuthDioSingleton._internal();

  static final AuthDioSingleton _singleton = AuthDioSingleton._internal();

  static AuthDioSingleton get instance => _singleton;

  AppDioClient? _client;

  AppDioClient get _ensureClient {
    final client = _client ??= AppDioClient(
      service: NetworkServiceType.auth,
      extraInterceptors: () => [
        AuthRefreshInterceptor(
          dioProvider: () => dio,
          onSessionExpired: AuthGate.handleSessionExpired,
        ),
      ],
    )..create();
    return client;
  }

  Dio get dio => _ensureClient.dio;

  void create() => _ensureClient;

  /// Attaches (or clears, with null) the access token on later auth calls —
  /// refresh, logout, session listing.
  void update(String? auth) {
    if (_client == null && (auth == null || auth.isEmpty)) {
      return;
    }
    _ensureClient.update(auth);
  }

  void tempBaseUpdate({String? url}) => _ensureClient.tempBaseUpdate(url: url);
}

Future<Response> authPostHttp(
  String path, {
  dynamic data,
  RequestFailureMetadata? requestMetadata,
}) => _runWithScopedCancelToken(
  (cancelToken) => AuthDioSingleton.instance.dio.post(
    path,
    data: data,
    cancelToken: cancelToken,
    options: Options(
      extra: RequestFailureMetadata.mergeIntoExtra(null, requestMetadata),
    ),
  ),
);

Future<Response> authGetHttp(
  String path, {
  Map<String, dynamic>? query,
  RequestFailureMetadata? requestMetadata,
}) => _runWithScopedCancelToken(
  (cancelToken) => AuthDioSingleton.instance.dio.get(
    path,
    queryParameters: query,
    cancelToken: cancelToken,
    options: Options(
      extra: RequestFailureMetadata.mergeIntoExtra(null, requestMetadata),
    ),
  ),
);

Future<Response> _runWithScopedCancelToken(
  Future<Response> Function(CancelToken cancelToken) request,
) async {
  final scope = RequestCancelScope.current;
  final lease = scope?.createTokenLease();
  final token = lease?.token ?? CancelToken();

  try {
    return await request(token);
  } finally {
    lease?.complete();
  }
}
