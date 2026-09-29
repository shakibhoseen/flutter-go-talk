import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

final class Logger extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!kDebugMode) {
      return super.onRequest(options, handler);
    }
    log("= = = Dio Request = = =");
    log("${_sanitizeHeaders(options.headers)}");
    log("${options.data}");
    log("${options.queryParameters}");
    log("${options.contentType}");
    log("${options.extra}");
    log("${options.baseUrl}${options.path}");
    return super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!kDebugMode) {
      return super.onResponse(response, handler);
    }
    log("= = = Dio Success Response = = =");
    log(json.encode(response.data));
    log("${response.requestOptions}");
    log("${response.statusCode}");
    log("${response.statusMessage}");
    log("${response.headers}");
    log("${response.extra}");

    return super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.type == DioExceptionType.cancel) {
      return super.onError(err, handler);
    }
    if (kDebugMode) {
      log("= = = Dio Error Response = = =");
      log('Error Response: ${err.response}');
      log('Error Message: ${err.message}');
      log('Error Type: ${err.type}');
      log('Error: ${err.error}');
      log(
        'Error Req option: ${err.requestOptions.path}\n${err.requestOptions.data}cart',
      );
    }
    //ErrorHandler.handle(err).failure; /// have to extend
    return super.onError(err, handler);
  }

  Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    return headers.map((key, value) {
      final isAuthorization = key.toLowerCase() == 'authorization';
      return MapEntry(key, isAuthorization ? 'Bearer ***' : value);
    });
  }
}
