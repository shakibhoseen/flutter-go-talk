import '../exception_handler/data_source.dart';

class CustomPagination<T> {
  int? currentPage;
  List<T>? data;
  String? firstPageUrl;
  int? from;
  int? lastPage;
  String? lastPageUrl;
  List<Links>? links;
  String? nextPageUrl;
  String? path;
  int? perPage;
  String? prevPageUrl;
  int? to;
  int? total;
  Flags? flags;

  final T Function(Map<String, dynamic> json) fromJsonFactory;
  final Map<String, dynamic> Function(T model) toJsonFactory;

  CustomPagination({
    this.currentPage,
    this.data,
    this.firstPageUrl,
    this.from,
    this.lastPage,
    this.lastPageUrl,
    this.links,
    this.nextPageUrl,
    this.path,
    this.perPage,
    this.prevPageUrl,
    this.to,
    this.total,
    required this.fromJsonFactory,
    required this.toJsonFactory,
  });

  CustomPagination.fromJson({
    required Map<String, dynamic> json,
    required this.fromJsonFactory,
    required this.toJsonFactory,
  }) {
    currentPage = json['current_page'];
    if (json['data'] != null) {
      data = <T>[];
      json['data'].forEach((v) {
        data!.add(fromJsonFactory(v));
      });
    }
    firstPageUrl = json['first_page_url'];
    from = json['from'];
    lastPage = json['last_page'];
    lastPageUrl = json['last_page_url'];
    if (json['links'] != null) {
      links = <Links>[];
      json['links'].forEach((v) {
        links!.add(Links.fromJson(v));
      });
    }
    nextPageUrl = json['next_page_url'];
    path = json['path'];
    perPage = json['per_page'];
    prevPageUrl = json['prev_page_url'];
    to = json['to'];
    total = json['total'];
    flags = json['flags'] != null ? Flags.fromJson(json['flags']) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['current_page'] = currentPage;
    if (this.data != null) {
      data['data'] = this.data!.map((v) => toJsonFactory(v)).toList();
    }
    data['first_page_url'] = firstPageUrl;
    data['from'] = from;
    data['last_page'] = lastPage;
    data['last_page_url'] = lastPageUrl;
    if (links != null) {
      data['links'] = links!.map((v) => v.toJson()).toList();
    }
    data['next_page_url'] = nextPageUrl;
    data['path'] = path;
    data['per_page'] = perPage;
    data['prev_page_url'] = prevPageUrl;
    data['to'] = to;
    data['total'] = total;
    if (flags != null) {
      data['flags'] = flags!.toJson();
    }
    return data;
  }
}

class Links {
  String? url;
  String? label;
  bool? active;

  Links({this.url, this.label, this.active});

  Links.fromJson(Map<String, dynamic> json) {
    url = json['url'];
    label = json['label'];
    active = json['active'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['url'] = url;
    data['label'] = label;
    data['active'] = active;
    return data;
  }
}

class CustomParentPagination<T> {
  String? message;
  CustomPagination<T>? data;
  bool? success;

  CustomParentPagination.customDefine(
    this.fromJsonFactory,
    this.toJsonFactory,
    this.data,
  );

  final T Function(Map<String, dynamic> json) fromJsonFactory;
  final Map<String, dynamic> Function(T model) toJsonFactory;

  CustomParentPagination.fromJson({
    required Map<String, dynamic> json,
    required this.fromJsonFactory,
    required this.toJsonFactory,
  }) {
    final businessFailure = ErrorHandler.tryResolveBusinessFailure(
      json,
      debugMessage: 'CustomParentPagination received success:false payload',
    );
    if (businessFailure != null) {
      throw businessFailure;
    }

    data = json['data'] != null
        ? CustomPagination.fromJson(
            json: json['data'],
            fromJsonFactory: (json) => fromJsonFactory(json),
            toJsonFactory: (model) => toJsonFactory(model),
          )
        : null;
    message = json['message'];
    success = json['success'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (this.data != null) {
      data['data'] = this.data!.toJson();
    }
    data['message'] = message;
    return data;
  }

  CustomPagination<T> requireData({
    String debugContext = 'CustomParentPagination data is null',
  }) {
    final value = data;
    if (value == null) {
      throw Failure.missingData(debugMessage: debugContext);
    }
    return value;
  }
}

class Flags {
  bool? isRandom;

  Flags({this.isRandom});

  Flags.fromJson(Map<String, dynamic> json) {
    isRandom = json['is_random'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['is_random'] = isRandom;
    return data;
  }
}
