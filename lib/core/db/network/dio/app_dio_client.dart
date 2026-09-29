import 'package:dio/dio.dart';

import '../endpoints.dart';
import '../network_base_url_resolver.dart';
import '../network_service_type.dart';
import 'app_header_interceptor.dart';
import 'log.dart';

final class AppDioClient {
  AppDioClient({required this.service, this.extraInterceptors});

  final NetworkServiceType service;

  /// Interceptors this service needs on top of the shared ones. Built per
  /// [Dio], because a token update replaces the instance.
  final List<Interceptor> Function()? extraInterceptors;
  late Dio dio;
  bool _isCreated = false;

  String get baseUrl => NetworkBaseUrlResolver.resolve(service);

  void create() {
    _rebuild();
  }

  void update(String? auth) {
    _rebuild(
      authorizationHeader: auth == null || auth.isEmpty ? null : 'Bearer $auth',
    );
  }

  void tempBaseUpdate({String? url}) {
    if (url == null || url.trim().isEmpty) {
      NetworkBaseUrlResolver.clearDebugOverride(service);
    } else {
      NetworkBaseUrlResolver.setDebugOverride(service, url);
    }

    _rebuild(authorizationHeader: _currentAuthorizationHeader);
  }

  String? get _currentAuthorizationHeader {
    if (!_isCreated) {
      return null;
    }

    final header = dio.options.headers[NetworkConstants.AUTHORIZATION];
    return header is String && header.isNotEmpty ? header : null;
  }

  void _rebuild({String? authorizationHeader}) {
    final options = BaseOptions(
      baseUrl: baseUrl,
      responseType: ResponseType.json,
      connectTimeout: const Duration(milliseconds: 100000),
      receiveTimeout: const Duration(milliseconds: 100000),
      headers: {
        NetworkConstants.ACCEPT: NetworkConstants.ACCEPT_TYPE,
        if (authorizationHeader != null)
          NetworkConstants.AUTHORIZATION: authorizationHeader,
      },
    );

    dio = Dio(options)
      ..interceptors.add(AppHeaderInterceptor())
      ..interceptors.add(Logger())
      ..interceptors.addAll(extraInterceptors?.call() ?? const []);
    _isCreated = true;
  }
}
