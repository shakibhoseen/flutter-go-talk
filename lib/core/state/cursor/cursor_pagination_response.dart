import '../../db/network/response/custom_pagination.dart';

class CursorPaginationResponse<T> {
  String? current;
  List<T>? data;
  String? nextCursor;
  String? prevCursor;
  int? total;
  Flags? flags;
  Map<String, dynamic>? extra;
  bool? hasMore;
  int? nextSinceId;

  final T Function(Map<String, dynamic> json) fromJsonFactory;
  final Map<String, dynamic> Function(T model) toJsonFactory;

  CursorPaginationResponse({
    this.current,
    this.data,
    this.nextCursor,
    this.prevCursor,
    this.total,
    this.flags,
    this.extra,
    this.hasMore,
    this.nextSinceId,
    required this.fromJsonFactory,
    required this.toJsonFactory,
  });

  CursorPaginationResponse.fromJson(
      {required Map<String, dynamic> json,
      required this.fromJsonFactory,
      required this.toJsonFactory}) {
    current = json['current_page'];
    if (json['data'] != null) {
      data = <T>[];
      json['data'].forEach((v) {
        data!.add(fromJsonFactory(v));
      });
    }
    nextCursor = json['next_page_url'];
    prevCursor = json['prev_page_url'];
    total = json['total'];
    flags = json['flags'] != null ? Flags.fromJson(json['flags']) : null;
    extra = json['extra'] is Map ? Map<String, dynamic>.from(json['extra']) : null;
    hasMore = json['has_more'] as bool?;
    nextSinceId = json['next_since_id'] is int
        ? json['next_since_id'] as int
        : (json['next_since_id'] != null
            ? int.tryParse(json['next_since_id'].toString())
            : null);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['current_page'] = current;
    if (this.data != null) {
      data['data'] = this.data!.map((v) => toJsonFactory(v)).toList();
    }

    data['next_page_url'] = nextCursor;
    data['prev_page_url'] = prevCursor;
    data['total'] = total;
    if (flags != null) {
      data['flags'] = flags!.toJson();
    }
    if (extra != null) {
      data['extra'] = extra;
    }
    if (hasMore != null) {
      data['has_more'] = hasMore;
    }
    if (nextSinceId != null) {
      data['next_since_id'] = nextSinceId;
    }
    return data;
  }
}
