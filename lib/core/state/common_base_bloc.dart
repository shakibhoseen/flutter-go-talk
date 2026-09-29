import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:either_dart/either.dart';
import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../db/network/exception_handler/data_source.dart';
import '../db/network/exception_handler/error_response.dart';
import '../db/network/response/custom_pagination.dart';
import '../db/network/dio/request_cancel_scope.dart';
import 'model/list_and_page_holder.dart';

part 'common_events.dart';

part 'common_states.dart';

abstract class CommonBloc<Event, BlocState, SuccessResponseType>
    extends Bloc<Event, BlocState> {
  CommonBloc(super.initialState) {
    on<Event>(_mapEventToState);
  }

  Map<String, dynamic>? currentQuery;
  final RequestCancelScope requestCancelScope = RequestCancelScope();
  BlocState? _lastSettledState;

  // @override
  Future<void> _mapEventToState(Event event, Emitter<BlocState> emit) async {
    if (event is ResetEvent) {
      onReset(event);
      emit(const InitialState() as BlocState);
      return;
    }
    if (event is SyncLocalPaginationStateEvent) {
      emit(
        SuccessWithPaginationState<SuccessResponseType>(
          data: event.data as SuccessResponseType,
          hasCleared: event.hasCleared,
        )
        as BlocState,
      );
      return;
    }
    final previousSettledState = _captureLastSettledState();
    emit(resolveLoadingState(event) as BlocState);
    try {
      if (event is FetchDataWithQueryEvent) {
        currentQuery = event.query;
      }
      final streamBuilder = eventStreamBuilder;
      if (streamBuilder != null) {
        // The stream is built *inside* the cancel scope on purpose: the zone it
        // installs is what lets the requests it makes pick up a cancel token.
        // Built outside, cancellation would silently stop working.
        await requestCancelScope.run(() async {
          await for (final data in streamBuilder(event)) {
            final successState = SuccessState(data) as BlocState;
            _rememberSettledState(successState);
            emit(successState);
          }
        });
      } else {
        final data = await requestCancelScope.run(() => handleEvent(event));
        final successState = SuccessState(data) as BlocState;
        _rememberSettledState(successState);
        emit(successState);
      }
    } catch (e) {
      final errorState = ErrorState.fromError(e);
      if (errorState.isCancellation) {
        if (previousSettledState != null) {
          emit(previousSettledState);
        } else {
          emit(const InitialState() as BlocState);
        }
        return;
      }

      final failureState = errorState as BlocState;
      _rememberSettledState(failureState);
      emit(failureState);
    }
  }

  Future<SuccessResponseType> handleEvent(Event event);

  /// Opt-in hook for events that answer more than once — a cached copy first,
  /// then the refreshed one.
  ///
  /// Return null (the default) and the bloc keeps its original single-answer
  /// behaviour through [handleEvent], so blocs that do not override this are
  /// untouched. A builder is returned rather than a stream so the bloc can
  /// decide *whether* to stream without creating one, and then build it inside
  /// the cancel scope.
  ///
  /// Each emission becomes a [SuccessState]. Suppressing an emission when
  /// nothing changed belongs in the repository, not here — see
  /// `BaseCachedRepository.cachedStream`.
  Stream<SuccessResponseType> Function(Event event)? get eventStreamBuilder =>
      null;

  Widget build({
    Key? key,
    required Widget Function(BuildContext context, BlocState state) builder,
    bool Function(BlocState previous, BlocState current)? buildWhen,
  }) {
    return BlocBuilder(
      bloc: this,
      builder: builder,
      key: key,
      buildWhen: buildWhen,
    );
  }

  bool getIsLoading() => state is LoadingState;

  void resetState() {
    add(const ResetEvent.stateOnly() as Event);
  }

  void resetKeepingQuery() {
    add(const ResetEvent.keepQuery() as Event);
  }

  void resetFully() {
    add(const ResetEvent.full() as Event);
  }

  @protected
  LoadingState resolveLoadingState(Event event) {
    if (event is FetchDataWithQueryEvent && state is SuccessState) {
      return const LoadingState.refresh();
    }
    return const LoadingState.initial();
  }

  BlocState? _captureLastSettledState() {
    if (state is! LoadingState) {
      _rememberSettledState(state);
    }
    return _lastSettledState;
  }

  void _rememberSettledState(BlocState value) {
    if (value is LoadingState) {
      return;
    }
    _lastSettledState = value;
  }

  @mustCallSuper
  @protected
  void onReset(ResetEvent event) {
    requestCancelScope.cancelActive(reason: 'bloc reset');
    _lastSettledState = null;
    if (event.clearsQuery) {
      currentQuery = null;
    }
  }

  @override
  Future<void> close() {
    requestCancelScope.close(reason: 'bloc closed');
    return super.close();
  }
}

enum ResetPin { on, off } // page should be cleared

//this is a common base class for pagination handle
abstract class CommonPaginationBloc<Event, BlocState, SuccessResponseType>
    extends Bloc<Event, BlocState> {
  CommonPaginationBloc(super.initialState) {
    on<Event>(_mapEventToState);
  }

  int totalPage = 0, currentPage = 0;
  Map<String, dynamic>? currentQuery;

  String? nextPage = '';
  final RequestCancelScope requestCancelScope = RequestCancelScope();
  BlocState? _lastSettledState;

  // @override
  Future<void> _mapEventToState(Event event, Emitter<BlocState> emit) async {
    if (event is ResetEvent) {
      onReset(event);
      emit(const InitialState() as BlocState);
      return;
    }
    if (event is SyncLocalPaginationStateEvent) {
      emit(
        SuccessWithPaginationState<SuccessResponseType>(
          data: event.data as SuccessResponseType,
          hasCleared: event.hasCleared,
        )
        as BlocState,
      );
      return;
    }
    final previousSettledState = _captureLastSettledState();
    emit(resolveLoadingState(event) as BlocState);
    try {
      //handle query has same will delete all page and total page;
      ResetPin resetPin = _checkQueryOperation(event);
      if (getIsNoPageAvailable()) {
        emit(const InitialState() as BlocState);
        return;
      }
      final data = await requestCancelScope.run(() => handleEvent(event));
      if (data.isLeft) {
        /// just only page loading or no page available then its must skip to emit
        /// old data store means pagination with query;
        final res = SuccessWithPaginationState<SuccessResponseType>(
          data: data.left,
          hasCleared: resetPin == ResetPin.on,
          //eventObject: event,
        );
        doActionBeforeEmitSuccessWithPaginationState(res);
        final successState = res as BlocState;
        _rememberSettledState(successState);
        emit(successState);
      } else {
        //initial state
        emit(const InitialState() as BlocState);
      }
    } catch (e) {
      final errorState = ErrorState.fromError(e);
      if (errorState.isCancellation) {
        if (previousSettledState != null) {
          emit(previousSettledState);
        } else {
          emit(const InitialState() as BlocState);
        }
        return;
      }

      final failureState = errorState as BlocState;
      _rememberSettledState(failureState);
      emit(failureState);
    }
  }

  ///just handle execution outside
  Future<Either<SuccessResponseType, String>> handleEvent(Event event);

  void doActionBeforeEmitSuccessWithPaginationState(
      SuccessWithPaginationState<SuccessResponseType> state,
      ) {
    //override if needed
  }

  ///handle pagination with query, when pin is on thant means query is changed and saved data need to cleared
  ResetPin _checkQueryOperation(Event event) {
    var resetPin = ResetPin.off;
    if (!const DeepCollectionEquality().equals(
      event is FetchDataWithQueryEvent ? event.query : null,
      currentQuery,
    ) ||
        _isClearPageWithData(event)) {
      //reset
      totalPage = 0;
      currentPage = 0;
      nextPage = '';
      resetPin = ResetPin.on;
    }
    if (event is FetchDataWithQueryEvent) {
      currentQuery = event.query;
    }
    return resetPin;
  }

  bool _isClearPageWithData(Event event) {
    if (event is CommonEvent) {
      return event.clearPageWithNewData ?? false;
    }
    return false;
  }

  /// common pagination bloc will handle
  void setPages({CustomPagination? model}) {
    if (model == null) return;
    if (currentPage < (model.currentPage ?? 0)) {
      currentPage = model.currentPage ?? 0;
    }
    totalPage = model.lastPage ?? 0;
    nextPage = model.nextPageUrl;
  }

  bool getIsLoading() => state is LoadingState;

  void resetState() {
    add(const ResetEvent.stateOnly() as Event);
  }

  void resetKeepingQuery() {
    add(const ResetEvent.keepQuery() as Event);
  }

  void resetFully() {
    add(const ResetEvent.full() as Event);
  }

  @protected
  LoadingState resolveLoadingState(Event event) {
    if (event is FetchDataWithQueryEvent && currentPage > 0) {
      return const LoadingState.pagination();
    }
    if (event is FetchDataWithQueryEvent &&
        state is SuccessWithPaginationState) {
      return const LoadingState.refresh();
    }
    return const LoadingState.initial();
  }

  BlocState? _captureLastSettledState() {
    if (state is! LoadingState) {
      _rememberSettledState(state);
    }
    return _lastSettledState;
  }

  void _rememberSettledState(BlocState value) {
    if (value is LoadingState) {
      return;
    }
    _lastSettledState = value;
  }

  @mustCallSuper
  @protected
  void onReset(ResetEvent event) {
    requestCancelScope.cancelActive(reason: 'pagination bloc reset');
    _lastSettledState = null;
    if (event.clearsData) {
      totalPage = 0;
      currentPage = 0;
      nextPage = '';
    }
    if (event.clearsQuery) {
      currentQuery = null;
    }
  }

  bool getIsNoPageAvailable() =>
      totalPage <= currentPage && totalPage > 0 || nextPage == null;

  Widget build({
    Key? key,
    required Widget Function(BuildContext context, BlocState state) builder,
    bool Function(BlocState previous, BlocState current)? buildWhen,
  }) {
    return BlocBuilder(
      bloc: this,
      builder: builder,
      key: key,
      buildWhen: buildWhen,
    );
  }

  ///new test getSimplifiedData
  void getSimplifyData(
      SuccessWithPaginationState state,
      ListAndPageHolder listAndPageHolder,
      ) {
    //log('id is $id and state id is ');
    final model = state.data as CustomPagination;
    if (state.hasCleared) {
      listAndPageHolder.list.clear();
    } else if (listAndPageHolder.currentPage >= currentPage) {
      return;
    }
    listAndPageHolder.currentPage = currentPage;
    final list = model.data ?? [];
    log('${list.length}');
    listAndPageHolder.list.addAll(list);
  }

  void refresh() {
    add(
      FetchDataWithQueryEvent(clearPageWithNewData: true, query: currentQuery)
      as Event,
    );
  }

  @override
  Future<void> close() {
    requestCancelScope.close(reason: 'pagination bloc closed');
    return super.close();
  }
}
