import 'package:dio/dio.dart';

import '../db/network/dio/dio.dart';
import '../db/network/exception_handler/data_source.dart';

/// Every network read in the app goes through here, so "what counts as a
/// failure" is decided once: a missing status code, a non-2xx, and a 2xx whose
/// body says `success:false` are all failures, and all of them arrive at the
/// caller as a [Failure].
abstract class _BaseGlobalDataApi {
  Future<dynamic> safeRequest(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final response = await request();
      final statusCode = response.statusCode;
      if (statusCode == null) {
        throw DataSource.badRequest.getFailure();
      }
      if (statusCode < 200 || statusCode >= 300) {
        throw DataSource.defaults.getFailure().copyWith(
          responseCode: statusCode,
          debugMessage: 'Unexpected non-2xx response without Dio exception',
        );
      }

      final businessFailure = ErrorHandler.tryResolveBusinessFailure(
        response.data,
        debugMessage:
            'Received success:false 2xx response for '
            '${response.requestOptions.path}',
        requestOptions: response.requestOptions,
      );
      if (businessFailure != null) {
        throw businessFailure;
      }
      return response.data;
    } catch (error) {
      throw ErrorHandler.resolve(error);
    }
  }
}

/// The shop API. Other services get their own subclass rather than a flag —
/// each one has its own base url and its own client.
class GlobalDataApi extends _BaseGlobalDataApi {
  GlobalDataApi._internal();

  static final GlobalDataApi _singleton = GlobalDataApi._internal();

  static GlobalDataApi get instance => _singleton;

  Future<dynamic> getResponse({
    required String url,
    Map<String, dynamic>? query,
    RequestFailureMetadata? requestMetadata,
  }) {
    return safeRequest(
      () => getHttp(url, query: query, requestMetadata: requestMetadata),
    );
  }

  Future<dynamic> postResponse({
    required String url,
    dynamic data,
    void Function(int sent, int total)? onSendProgress,
    RequestFailureMetadata? requestMetadata,
  }) {
    return safeRequest(
      () => postHttp(
        url,
        data: data,
        onSendProgress: onSendProgress,
        requestMetadata: requestMetadata,
      ),
    );
  }

  Future<dynamic> putResponse({
    required String url,
    dynamic data,
    void Function(int sent, int total)? onSendProgress,
    RequestFailureMetadata? requestMetadata,
  }) {
    return safeRequest(
      () => putHttp(
        url,
        data: data,
        onSendProgress: onSendProgress,
        requestMetadata: requestMetadata,
      ),
    );
  }

  Future<dynamic> deleteResponse({
    required String url,
    dynamic data,
    RequestFailureMetadata? requestMetadata,
  }) {
    return safeRequest(
      () => deleteHttp(url, data: data, requestMetadata: requestMetadata),
    );
  }
}
