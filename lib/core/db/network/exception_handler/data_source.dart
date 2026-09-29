import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart';

import '../endpoints.dart';
import '../response/custom_response_parse.dart';
import 'error_response.dart';

enum DataSource {
  success,
  noContent,
  badRequest,
  forbidden,
  unauthorised,
  notFound,
  fileTooLarge,
  internalServerError,
  connectTimeOut,
  cancel,
  receiveTimeOut,
  sendTimeOut,
  cacheError,
  noInternetConnection,
  defaults,
}

enum ErrorDisplayType { none, inline, toast, screen, dialog }

enum FailureAction { none, logout, maintenance, forceUpdate }

final class RequestFailureMetadata {
  const RequestFailureMetadata({
    this.isAuthRequest,
    this.ignoreGlobal401,
    this.silent,
    this.preferredDisplayType,
  });

  static const String _isAuthRequestKey = 'error.is_auth_request';
  static const String _ignoreGlobal401Key = 'error.ignore_global_401';
  static const String _silentKey = 'error.silent';
  static const String _preferredDisplayTypeKey = 'error.preferred_display_type';

  final bool? isAuthRequest;
  final bool? ignoreGlobal401;
  final bool? silent;
  final ErrorDisplayType? preferredDisplayType;

  Map<String, dynamic> toExtra() {
    return {
      if (isAuthRequest != null) _isAuthRequestKey: isAuthRequest,
      if (ignoreGlobal401 != null) _ignoreGlobal401Key: ignoreGlobal401,
      if (silent != null) _silentKey: silent,
      if (preferredDisplayType != null)
        _preferredDisplayTypeKey: preferredDisplayType!.name,
    };
  }

  RequestFailureMetadata copyWith({
    bool? isAuthRequest,
    bool? ignoreGlobal401,
    bool? silent,
    ErrorDisplayType? preferredDisplayType,
  }) {
    return RequestFailureMetadata(
      isAuthRequest: isAuthRequest ?? this.isAuthRequest,
      ignoreGlobal401: ignoreGlobal401 ?? this.ignoreGlobal401,
      silent: silent ?? this.silent,
      preferredDisplayType: preferredDisplayType ?? this.preferredDisplayType,
    );
  }

  static Map<String, dynamic>? mergeIntoExtra(
    Map<String, dynamic>? extra,
    RequestFailureMetadata? metadata,
  ) {
    if ((extra == null || extra.isEmpty) && metadata == null) {
      return null;
    }

    return {...?extra, ...?metadata?.toExtra()};
  }

  static RequestFailureMetadata fromRequestOptions(
    RequestOptions requestOptions,
  ) {
    return fromExtra(requestOptions.extra);
  }

  static RequestFailureMetadata fromExtra(Map<String, dynamic>? extra) {
    final preferredDisplayTypeRaw = extra?[_preferredDisplayTypeKey];
    return RequestFailureMetadata(
      isAuthRequest: _readBool(extra?[_isAuthRequestKey]),
      ignoreGlobal401: _readBool(extra?[_ignoreGlobal401Key]),
      silent: _readBool(extra?[_silentKey]),
      preferredDisplayType: _readDisplayType(preferredDisplayTypeRaw),
    );
  }

  static bool? _readBool(dynamic value) {
    return switch (value) {
      bool boolValue => boolValue,
      String stringValue => switch (stringValue.trim().toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => null,
      },
      _ => null,
    };
  }

  static ErrorDisplayType? _readDisplayType(dynamic value) {
    if (value is ErrorDisplayType) {
      return value;
    }
    if (value is! String) {
      return null;
    }

    for (final displayType in ErrorDisplayType.values) {
      if (displayType.name == value) {
        return displayType;
      }
    }

    return null;
  }
}

final class FailureActionEvent {
  const FailureActionEvent({required this.id, required this.failure});

  final int id;
  final Failure failure;
}

final class FailureActionChannel {
  FailureActionChannel._();

  static final StreamController<FailureActionEvent> _controller =
      StreamController<FailureActionEvent>.broadcast(sync: true);
  static FailureActionEvent? _pendingEvent;
  static int _nextEventId = 0;

  static Stream<FailureActionEvent> get stream => _controller.stream;

  static FailureActionEvent? get pendingEvent => _pendingEvent;

  static void dispatch(Failure failure) {
    if (!failure.hasGlobalAction) {
      return;
    }

    final currentPending = _pendingEvent;
    if (currentPending != null &&
        currentPending.failure.action == failure.action &&
        currentPending.failure.responseCode == failure.responseCode) {
      return;
    }

    final event = FailureActionEvent(id: ++_nextEventId, failure: failure);
    _pendingEvent = event;
    _controller.add(event);
  }

  static void markHandled(int eventId) {
    if (_pendingEvent?.id == eventId) {
      _pendingEvent = null;
    }
  }

  static void reset() {
    _pendingEvent = null;
    _nextEventId = 0;
  }
}

extension DataSourceExtension on DataSource {
  Failure getFailure() {
    switch (this) {
      case DataSource.success:
        return const Failure(
          ResponseCode.SUCCESS,
          ResponseMessage.SUCCESS,
          shouldShowToUser: false,
          displayType: ErrorDisplayType.none,
        );
      case DataSource.noContent:
        return const Failure(
          ResponseCode.NO_CONTENT,
          ResponseMessage.NO_CONTENT,
          shouldShowToUser: false,
          displayType: ErrorDisplayType.none,
        );
      case DataSource.badRequest:
        return const Failure(
          ResponseCode.BAD_REQUEST,
          ResponseMessage.BAD_REQUEST,
        );
      case DataSource.forbidden:
        return const Failure(ResponseCode.FORBIDDEN, ResponseMessage.FORBIDDEN);
      case DataSource.unauthorised:
        return const Failure(
          ResponseCode.UNAUTHORISED,
          ResponseMessage.UNAUTHORISED,
        );
      case DataSource.notFound:
        return const Failure(
          ResponseCode.NOT_FOUND,
          ResponseMessage.NOT_FOUND,
          displayType: ErrorDisplayType.screen,
        );
      case DataSource.fileTooLarge:
        return const Failure(
          ResponseCode.FILE_TOO_LARGE,
          ResponseMessage.FILE_TOO_LARGE,
        );
      case DataSource.internalServerError:
        return const Failure(
          ResponseCode.INTERNAL_SERVER_ERROR,
          ResponseMessage.INTERNAL_SERVER_ERROR,
          isRetryable: true,
          displayType: ErrorDisplayType.screen,
        );
      case DataSource.connectTimeOut:
        return const Failure(
          ResponseCode.CONNECT_TIMEOUT,
          ResponseMessage.CONNECT_TIMEOUT,
          isRetryable: true,
        );
      case DataSource.cancel:
        return const Failure(
          ResponseCode.CANCEL,
          ResponseMessage.CANCEL,
          shouldShowToUser: false,
          displayType: ErrorDisplayType.none,
        );
      case DataSource.receiveTimeOut:
        return const Failure(
          ResponseCode.RECEIVED_TIMEOUT,
          ResponseMessage.RECIEVED_TIMEOUT,
          isRetryable: true,
        );
      case DataSource.sendTimeOut:
        return const Failure(
          ResponseCode.SEND_TIMEOUT,
          ResponseMessage.SEND_TIMEOUT,
          isRetryable: true,
        );
      case DataSource.cacheError:
        return const Failure(
          ResponseCode.CACHE_ERROR,
          ResponseMessage.CACHE_ERROR,
          shouldShowToUser: false,
        );
      case DataSource.noInternetConnection:
        return const Failure(
          ResponseCode.NO_INTERNET_CONNECTION,
          ResponseMessage.NO_INTERNET_CONNECTION,
          isRetryable: true,
        );
      case DataSource.defaults:
        return const Failure(ResponseCode.DEFAULT, ResponseMessage.DEFAULT);
    }
  }
}

final class Failure implements Exception {
  final int responseCode;
  final String responseMessage;
  final String? backendMessage;
  final String? backendErrorCode;
  final String? debugMessage;
  final bool shouldShowToUser;
  final bool isRetryable;
  final ErrorDisplayType displayType;
  final FailureAction action;
  final CustomValidationResponseParse? validationData;

  const Failure(
    this.responseCode,
    this.responseMessage, {
    this.backendMessage,
    this.backendErrorCode,
    this.debugMessage,
    this.shouldShowToUser = true,
    this.isRetryable = false,
    this.displayType = ErrorDisplayType.toast,
    this.action = FailureAction.none,
    this.validationData,
  });

  factory Failure.business({
    required String message,
    int responseCode = ResponseCode.BUSINESS_ERROR,
    String? backendMessage,
    String? backendErrorCode,
    String? debugMessage,
    bool shouldShowToUser = true,
    bool isRetryable = false,
    ErrorDisplayType displayType = ErrorDisplayType.toast,
    FailureAction action = FailureAction.none,
    CustomValidationResponseParse? validationData,
  }) {
    final trimmedMessage = message.trim();
    return Failure(
      responseCode,
      trimmedMessage.isEmpty ? ResponseMessage.BUSINESS_ERROR : trimmedMessage,
      backendMessage: backendMessage ?? trimmedMessage,
      backendErrorCode: backendErrorCode,
      debugMessage: debugMessage,
      shouldShowToUser: shouldShowToUser,
      isRetryable: isRetryable,
      displayType: displayType,
      action: action,
      validationData: validationData,
    );
  }

  factory Failure.invalidState({
    required String debugMessage,
    String userMessage = ResponseMessage.DEFAULT,
    int responseCode = ResponseCode.DEFAULT,
    bool shouldShowToUser = true,
    bool isRetryable = false,
    ErrorDisplayType displayType = ErrorDisplayType.toast,
    FailureAction action = FailureAction.none,
  }) {
    return Failure(
      responseCode,
      userMessage,
      debugMessage: debugMessage,
      shouldShowToUser: shouldShowToUser,
      isRetryable: isRetryable,
      displayType: displayType,
      action: action,
    );
  }

  factory Failure.missingData({
    required String debugMessage,
    String userMessage = ResponseMessage.DEFAULT,
    int responseCode = ResponseCode.DEFAULT,
    bool shouldShowToUser = true,
    ErrorDisplayType displayType = ErrorDisplayType.toast,
  }) {
    return Failure.invalidState(
      debugMessage: debugMessage,
      userMessage: userMessage,
      responseCode: responseCode,
      shouldShowToUser: shouldShowToUser,
      displayType: displayType,
    );
  }

  Failure copyWith({
    int? responseCode,
    String? responseMessage,
    String? backendMessage,
    String? backendErrorCode,
    String? debugMessage,
    bool? shouldShowToUser,
    bool? isRetryable,
    ErrorDisplayType? displayType,
    FailureAction? action,
    CustomValidationResponseParse? validationData,
  }) {
    return Failure(
      responseCode ?? this.responseCode,
      responseMessage ?? this.responseMessage,
      backendMessage: backendMessage ?? this.backendMessage,
      backendErrorCode: backendErrorCode ?? this.backendErrorCode,
      debugMessage: debugMessage ?? this.debugMessage,
      shouldShowToUser: shouldShowToUser ?? this.shouldShowToUser,
      isRetryable: isRetryable ?? this.isRetryable,
      displayType: displayType ?? this.displayType,
      action: action ?? this.action,
      validationData: validationData ?? this.validationData,
    );
  }

  bool get hasGlobalAction => action != FailureAction.none;

  @override
  String toString() => responseMessage;
}

final class ErrorHandler implements Exception {
  late Failure failure;

  ErrorHandler.handle(dynamic error, {bool triggerSideEffects = true}) {
    failure = resolve(error, triggerSideEffects: triggerSideEffects);
  }

  static Failure? tryResolveBusinessFailure(
    dynamic data, {
    String debugMessage = 'Received success:false business response',
    ErrorDisplayType displayType = ErrorDisplayType.toast,
    RequestOptions? requestOptions,
  }) {
    final map = switch (data) {
      Map<String, dynamic> value => value,
      Map value => Map<String, dynamic>.from(value),
      _ => null,
    };

    if (map == null || !_isExplicitBusinessFailure(map['success'])) {
      return null;
    }

    final backendMessage = _extractBackendMessage(map);
    final backendErrorCode = _extractBackendErrorCode(map);

    final requestMetadata = requestOptions == null
        ? const RequestFailureMetadata()
        : RequestFailureMetadata.fromRequestOptions(requestOptions);

    // Parse validation errors from response
    CustomValidationResponseParse? validationData;
    if (map['errors'] != null) {
      validationData = CustomValidationResponseParse.fromJson(map);
    }

    return Failure.business(
      message: backendMessage ?? ResponseMessage.BUSINESS_ERROR,
      backendMessage: backendMessage,
      backendErrorCode: backendErrorCode,
      debugMessage: debugMessage,
      displayType: requestMetadata.preferredDisplayType ?? displayType,
      validationData: validationData,
    );
  }

  static Failure resolve(dynamic error, {bool triggerSideEffects = true}) {
    final failure = switch (error) {
      Failure failure => failure,
      DioException dioError => _handleDioError(dioError),
      String message => DataSource.defaults.getFailure().copyWith(
        responseMessage: message.trim().isEmpty
            ? ResponseMessage.DEFAULT
            : message.trim(),
        debugMessage: message,
      ),
      _ => DataSource.defaults.getFailure().copyWith(
        debugMessage: error.toString(),
      ),
    };

    if (triggerSideEffects) {
      FailureActionChannel.dispatch(failure);
    }
    if (error is! DioException && error is! Failure && error is! String) {
      log(error.toString(), name: 'ErrorHandler');
    }
    return failure;
  }

  static Failure _handleDioError(DioException error) {
    if (error.type != DioExceptionType.cancel) {
      log('..........error type ${error.type}');
    }
    final requestMetadata = RequestFailureMetadata.fromRequestOptions(
      error.requestOptions,
    );
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return DataSource.connectTimeOut.getFailure().copyWith(
          debugMessage: error.message,
        );
      case DioExceptionType.sendTimeout:
        return DataSource.sendTimeOut.getFailure().copyWith(
          debugMessage: error.message,
        );
      case DioExceptionType.receiveTimeout:
        return DataSource.receiveTimeOut.getFailure().copyWith(
          debugMessage: error.message,
        );
      case DioExceptionType.badResponse:
        final response = error.response;
        final statusCode = response?.statusCode;
        if (response == null || statusCode == null) {
          return DataSource.defaults.getFailure().copyWith(
            debugMessage: error.message,
          );
        }
        final requestPath = error.requestOptions.path;
        final backendMessage = _extractBackendMessage(response.data);
        final backendErrorCode = _extractBackendErrorCode(response.data);
        final validationData = _parseValidationData(response.data);

        switch (statusCode) {
          case ResponseCode.UNPROCESSABLE_ENTITY:
            final validationText = validationData?.validationText ?? 
                _extractValidationMessage(response.data);
            return _applyRequestMetadata(
              Failure(
                statusCode,
                validationText.isEmpty
                    ? (backendMessage ?? ResponseMessage.VALIDATION_ERROR)
                    : validationText,
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
                displayType:
                    requestMetadata.preferredDisplayType ??
                    ErrorDisplayType.inline,
                validationData: validationData,
              ),
              requestMetadata,
            );
          case ResponseCode.UNAUTHORISED:
            if (_isAuthRequest(requestPath, requestMetadata)) {
              return _applyRequestMetadata(
                Failure(
                  statusCode,
                  _resolveAuthMessage(requestPath, backendMessage),
                  backendMessage: backendMessage,
                  backendErrorCode: backendErrorCode,
                  debugMessage: error.message,
                ),
                requestMetadata,
              );
            }

            final shouldIgnoreReset = _shouldIgnoreUnauthorizedReset(
              requestPath,
              requestMetadata,
            );
            return _applyRequestMetadata(
              Failure(
                statusCode,
                ResponseMessage.SESSION_EXPIRED,
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
                shouldShowToUser: false,
                displayType: ErrorDisplayType.none,
                action: shouldIgnoreReset
                    ? FailureAction.none
                    : FailureAction.logout,
              ),
              requestMetadata,
            );
          case ResponseCode.BAD_REQUEST:
            return _applyRequestMetadata(
              Failure(
                statusCode,
                _resolveClientMessage(
                  statusCode: statusCode,
                  backendMessage: backendMessage,
                  fallbackMessage: ResponseMessage.BAD_REQUEST,
                ),
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
                validationData: validationData,
              ),
              requestMetadata,
            );
          case ResponseCode.FORBIDDEN:
            return _applyRequestMetadata(
              Failure(
                statusCode,
                _resolveClientMessage(
                  statusCode: statusCode,
                  backendMessage: backendMessage,
                  fallbackMessage: ResponseMessage.FORBIDDEN,
                ),
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
              ),
              requestMetadata,
            );
          case ResponseCode.NOT_FOUND:
            return _applyRequestMetadata(
              Failure(
                statusCode,
                _resolveClientMessage(
                  statusCode: statusCode,
                  backendMessage: backendMessage,
                  fallbackMessage: ResponseMessage.NOT_FOUND,
                ),
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
                displayType: ErrorDisplayType.screen,
              ),
              requestMetadata,
            );
          case ResponseCode.CONFLICT:
            return _applyRequestMetadata(
              Failure(
                statusCode,
                _resolveClientMessage(
                  statusCode: statusCode,
                  backendMessage: backendMessage,
                  fallbackMessage: ResponseMessage.BAD_REQUEST,
                ),
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
              ),
              requestMetadata,
            );
          case ResponseCode.FILE_TOO_LARGE:
            return _applyRequestMetadata(
              DataSource.fileTooLarge.getFailure().copyWith(
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
              ),
              requestMetadata,
            );
          case ResponseCode.TOO_MANY_REQUESTS:
            return _applyRequestMetadata(
              Failure(
                statusCode,
                _resolveClientMessage(
                  statusCode: statusCode,
                  backendMessage: backendMessage,
                  fallbackMessage: ResponseMessage.TOO_MANY_REQUESTS,
                ),
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
                isRetryable: true,
              ),
              requestMetadata,
            );
          case ResponseCode.SERVICE_UNAVAILABLE:
            return _applyRequestMetadata(
              Failure(
                statusCode,
                ResponseMessage.MAINTENANCE,
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
                shouldShowToUser: false,
                displayType: ErrorDisplayType.none,
                action: FailureAction.maintenance,
              ),
              requestMetadata,
            );
          case ResponseCode.FORCE_UPDATE_REQUIRED:
            return _applyRequestMetadata(
              Failure(
                statusCode,
                ResponseMessage.FORCE_UPDATE,
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
                shouldShowToUser: false,
                displayType: ErrorDisplayType.none,
                action: FailureAction.forceUpdate,
              ),
              requestMetadata,
            );
          default:
            if (statusCode >= 500 && statusCode < 600) {
              return _applyRequestMetadata(
                DataSource.internalServerError.getFailure().copyWith(
                  backendMessage: backendMessage,
                  backendErrorCode: backendErrorCode,
                  debugMessage: error.message,
                ),
                requestMetadata,
              );
            }

            return _applyRequestMetadata(
              Failure(
                statusCode,
                _resolveClientMessage(
                  statusCode: statusCode,
                  backendMessage: backendMessage,
                  fallbackMessage:
                      response.statusMessage ?? ResponseMessage.DEFAULT,
                ),
                backendMessage: backendMessage,
                backendErrorCode: backendErrorCode,
                debugMessage: error.message,
              ),
              requestMetadata,
            );
        }
      case DioExceptionType.cancel:
        return DataSource.cancel.getFailure().copyWith(
          debugMessage: error.message,
        );
      case DioExceptionType.connectionError:
        return DataSource.noInternetConnection.getFailure().copyWith(
          debugMessage: error.message,
        );
      default:
        return DataSource.defaults.getFailure().copyWith(
          debugMessage: error.message ?? error.error?.toString(),
        );
    }
  }

  /// modify 401 request handle for all
  static Future<Failure> handelAuthenticatedCheck(dynamic error) async {
    final failure = ErrorHandler.resolve(error);
    return failure;
  }

  static Failure _applyRequestMetadata(
    Failure failure,
    RequestFailureMetadata requestMetadata,
  ) {
    if (requestMetadata.silent != true || failure.hasGlobalAction) {
      return failure;
    }

    return failure.copyWith(
      shouldShowToUser: false,
      displayType: ErrorDisplayType.none,
    );
  }

  static bool _shouldIgnoreUnauthorizedReset(
    String requestPath,
    RequestFailureMetadata requestMetadata,
  ) {
    if (requestMetadata.ignoreGlobal401 == true) {
      return true;
    }

    if (requestPath.contains('public-reels')) {
      return true;
    }

    final normalizedPath = requestPath.startsWith('/')
        ? requestPath.substring(1)
        : requestPath;
    final segments = normalizedPath.split('/');
    if (segments.length < 3 || segments.first != 'reels') {
      return false;
    }

    final action = segments.last;
    return action == 'views' || action == 'share';
  }

  static bool _isAuthRequest(
    String requestPath,
    RequestFailureMetadata requestMetadata,
  ) {
    if (requestMetadata.isAuthRequest != null) {
      return requestMetadata.isAuthRequest!;
    }

    final normalizedPath = requestPath.startsWith('/')
        ? requestPath.substring(1)
        : requestPath;

    return normalizedPath == Endpoints.login() ||
        normalizedPath == Endpoints.sendOtp() ||
        normalizedPath == Endpoints.forgetPassSentOtp() ||
        normalizedPath == Endpoints.verifyOtp() ||
        normalizedPath == Endpoints.register() ||
        normalizedPath == Endpoints.resetPassword() ||
        normalizedPath == Endpoints.setNewPassword() ||
        normalizedPath == Endpoints.parcelMerchantLogin();
  }

  static String _resolveAuthMessage(
    String requestPath,
    String? backendMessage,
  ) {
    if (_hasReadableBackendMessage(backendMessage)) {
      return backendMessage!;
    }

    final normalizedPath = requestPath.startsWith('/')
        ? requestPath.substring(1)
        : requestPath;
    if (normalizedPath == Endpoints.verifyOtp()) {
      return ResponseMessage.INVALID_OTP;
    }
    return ResponseMessage.INVALID_CREDENTIALS;
  }

  static String _resolveClientMessage({
    required int statusCode,
    required String? backendMessage,
    required String fallbackMessage,
  }) {
    if (_hasReadableBackendMessage(backendMessage) &&
        _shouldTrustBackendMessage(statusCode)) {
      return backendMessage!;
    }
    return fallbackMessage;
  }

  static bool _shouldTrustBackendMessage(int statusCode) {
    return statusCode == ResponseCode.BAD_REQUEST ||
        statusCode == ResponseCode.FORBIDDEN ||
        statusCode == ResponseCode.NOT_FOUND ||
        statusCode == ResponseCode.CONFLICT ||
        statusCode == ResponseCode.UNPROCESSABLE_ENTITY ||
        statusCode == ResponseCode.TOO_MANY_REQUESTS;
  }

  static bool _hasReadableBackendMessage(String? message) {
    return message != null && message.trim().isNotEmpty;
  }

  static bool _isExplicitBusinessFailure(dynamic success) {
    if (success is bool) {
      return success == false;
    }
    if (success is num) {
      return success == 0;
    }
    if (success is String) {
      final normalized = success.trim().toLowerCase();
      return normalized == 'false' || normalized == '0';
    }
    return false;
  }

  static String? _extractBackendMessage(dynamic data) {
    if (data is Map) {
      final message = data['message'] ?? _errorEnvelope(data)?['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return null;
  }

  static String? _extractBackendErrorCode(dynamic data) {
    if (data is Map) {
      final envelope = _errorEnvelope(data);
      final code =
          data['error_code'] ?? data['code'] ?? envelope?['code'];
      if (code is String && code.trim().isNotEmpty) {
        return code.trim();
      }
    }
    return null;
  }

  /// The accounts service nests its failure as
  /// `{"error": {"code": ..., "message": ...}}` rather than putting them at
  /// the top level like the shop API. Reading both here keeps every caller
  /// free of the difference.
  static Map? _errorEnvelope(Map data) {
    final error = data['error'];
    return error is Map ? error : null;
  }

  static String _extractValidationMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      try {
        return CustomValidationResponseParse.fromJson(
          data,
        ).validationText.trim();
      } catch (_) {
        return '';
      }
    }

    if (data is Map) {
      try {
        return CustomValidationResponseParse.fromJson(
          Map<String, dynamic>.from(data),
        ).validationText.trim();
      } catch (_) {
        return '';
      }
    }

    return '';
  }

  static CustomValidationResponseParse? _parseValidationData(dynamic data) {
    if (data is Map<String, dynamic> && data['errors'] != null) {
      try {
        return CustomValidationResponseParse.fromJson(data);
      } catch (_) {
        return null;
      }
    }
    if (data is Map && data['errors'] != null) {
      try {
        return CustomValidationResponseParse.fromJson(
          Map<String, dynamic>.from(data),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
