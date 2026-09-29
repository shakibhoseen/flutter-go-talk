import '../exception_handler/data_source.dart';

class CustomParentListResponse<T> {
  // all non pagination parent response have same response
  String? message;
  List<T>? data;
  bool? success;
  //CustomParentPagination._();

  final T Function(Map<String, dynamic> json) fromJsonFactory;
  final Map<String, dynamic> Function(T model) toJsonFactory;

  CustomParentListResponse.fromJson({
    required Map<String, dynamic> json,
    required this.fromJsonFactory,
    required this.toJsonFactory,
  }) {
    _throwIfBusinessFailure(
      json,
      debugMessage: 'CustomParentListResponse received success:false payload',
    );
    if (json['data'] != null) {
      data = <T>[];
      json['data'].forEach((v) {
        data!.add(fromJsonFactory(v));
      });
    }
    message = json['message'];
    success = json['success'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (this.data != null) {
      data['data'] = this.data?.map((e) => toJsonFactory(e)).toList();
    }
    data['message'] = message;
    return data;
  }

  List<T> requireData({
    String debugContext = 'CustomParentListResponse data is null',
  }) {
    final value = data;
    if (value == null) {
      throw Failure.missingData(debugMessage: debugContext);
    }
    return value;
  }
}

class CustomParentResponse<T> {
  // all non pagination parent response have same response
  String? message;
  T? data;
  bool? success;
  //CustomParentPagination._();

  final T Function(Map<String, dynamic> json) fromJsonFactory;
  final Map<String, dynamic> Function(T model) toJsonFactory;

  CustomParentResponse.fromJson({
    required Map<String, dynamic> json,
    required this.fromJsonFactory,
    required this.toJsonFactory,
  }) {
    _throwIfBusinessFailure(
      json,
      debugMessage: 'CustomParentResponse received success:false payload',
    );
    if (json['data'] != null) {
      data = fromJsonFactory(json['data']);
    }
    message = json['message'];
    success = json['success'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    final p = this.data;
    if (p != null) {
      data['data'] = toJsonFactory(p);
    }
    data['message'] = message;
    return data;
  }

  T requireData({String debugContext = 'CustomParentResponse data is null'}) {
    final value = data;
    if (value == null) {
      throw Failure.missingData(debugMessage: debugContext);
    }
    return value;
  }
}

void _throwIfBusinessFailure(
  Map<String, dynamic> json, {
  required String debugMessage,
}) {
  final businessFailure = ErrorHandler.tryResolveBusinessFailure(
    json,
    debugMessage: debugMessage,
  );
  if (businessFailure != null) {
    throw businessFailure;
  }
}
