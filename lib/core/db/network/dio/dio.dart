import 'package:dio/dio.dart';

import '../../../session/auth_gate.dart';
import '../exception_handler/data_source.dart';
import '../network_service_type.dart';
import 'app_dio_client.dart';
import 'auth_refresh_interceptor.dart';
import 'request_cancel_scope.dart';

final class DioSingleton {
  static final DioSingleton _singleton = DioSingleton._internal();

  DioSingleton._internal();

  static DioSingleton get instance => _singleton;

  AppDioClient? _client;

  AppDioClient get _ensureClient {
    final client = _client ??= AppDioClient(
      service: NetworkServiceType.chat,
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

  void create() {
    _ensureClient;
  }

  void update(String? auth) {
    if (_client == null && (auth == null || auth.isEmpty)) {
      return;
    }
    _ensureClient.update(auth);
  }

  void tempBaseUpdate({String? url}) {
    _ensureClient.tempBaseUpdate(url: url);
  }
}

Future<Response> postHttp(
  String path, {
  dynamic data,
  void Function(int sent, int total)? onSendProgress,
  RequestFailureMetadata? requestMetadata,
}) => _runWithScopedCancelToken(
  (cancelToken) => DioSingleton.instance.dio.post(
    path,
    data: data,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
    options: Options(
      extra: RequestFailureMetadata.mergeIntoExtra(null, requestMetadata),
    ),
  ),
);

Future<Response> putHttp(
  String path, {
  dynamic data,
  void Function(int sent, int total)? onSendProgress,
  RequestFailureMetadata? requestMetadata,
}) => _runWithScopedCancelToken(
  (cancelToken) => DioSingleton.instance.dio.put(
    path,
    data: data,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
    options: Options(
      extra: RequestFailureMetadata.mergeIntoExtra(null, requestMetadata),
    ),
  ),
);

Future<Response> getHttp(
  String path, {
  Map<String, dynamic>? query,
  RequestFailureMetadata? requestMetadata,
}) => _runWithScopedCancelToken(
  (cancelToken) => DioSingleton.instance.dio.get(
    path,
    cancelToken: cancelToken,
    queryParameters: query,
    options: Options(
      extra: RequestFailureMetadata.mergeIntoExtra(null, requestMetadata),
    ),
  ),
);

Future<Response> deleteHttp(
  String path, {
  dynamic data,
  RequestFailureMetadata? requestMetadata,
}) => _runWithScopedCancelToken(
  (cancelToken) => DioSingleton.instance.dio.delete(
    path,
    data: data,
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
