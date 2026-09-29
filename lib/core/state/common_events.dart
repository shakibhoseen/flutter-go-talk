part of 'common_base_bloc.dart';

enum ResetMode { stateOnly, keepQuery, full }

abstract class CommonEvent {
  final bool? clearPageWithNewData;

  const CommonEvent({this.clearPageWithNewData});
}

class FetchDataEvent extends CommonEvent {
  const FetchDataEvent({super.clearPageWithNewData});
}

class FetchDataWithQueryEvent extends CommonEvent {
  final Map<String, dynamic>? query;

  /// clear all data that will be many page loaded already and start from page 1 again
  const FetchDataWithQueryEvent({this.query, super.clearPageWithNewData});
}

class ResetEvent extends CommonEvent {
  final ResetMode mode;

  const ResetEvent({this.mode = ResetMode.stateOnly});

  const ResetEvent.stateOnly() : mode = ResetMode.stateOnly;

  const ResetEvent.keepQuery() : mode = ResetMode.keepQuery;

  const ResetEvent.full() : mode = ResetMode.full;

  bool get clearsData => mode != ResetMode.stateOnly;

  bool get clearsQuery => mode == ResetMode.full;
}

class SyncLocalPaginationStateEvent<T> extends CommonEvent {
  final T data;
  final bool hasCleared;

  const SyncLocalPaginationStateEvent({
    required this.data,
    this.hasCleared = false,
  });
}

///
/// scenario 1 we want to reset all data have current page, total page, next page but not query
/// scenario 2 we want to reset all data have current page, total page, next page and query
