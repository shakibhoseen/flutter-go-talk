import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../application/app_version/app_version_service.dart';

class AppHeaderInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.addAll({
      'X-App-Version': AppVersionService.appVersion,
      'X-Build-Number': AppVersionService.buildNumber,
      'X-Platform': Platform.isIOS ? 'ios' : 'android',
      // 'X-Checkout-Rule-Version': CheckoutRuleCache.version,
    });
    if (kDebugMode) {
      log(
        'app header interceptor version : ${AppVersionService.appVersion} ${AppVersionService.buildNumber}',
      );
    }
    handler.next(options);
  }
}
