import 'package:collection/collection.dart';
import 'package:either_dart/either.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../db/network/dio/request_cancel_scope.dart';
import '../common_base_bloc.dart';

import 'cursor_pagination_response.dart';

abstract class CursorPaginationBloc<Event, BlocState, SuccessResponseType>
    extends Bloc<Event, BlocState> {
  CursorPaginationBloc(super.initialState) {
    on<Event>(_mapEventToState);
  }

  int? totalItems;
  String? currentCursor;
  Map<String, dynamic>? currentQuery;
  String? nextCursor;
  bool? _noDataLeft;
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
        ) as BlocState,
      );
      return;
    }
    final previousSettledState = _captureLastSettledState();
    emit(_resolveLoadingState(event) as BlocState);
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

  void doActionBeforeEmitSuccessWithPaginationState(
    SuccessWithPaginationState<SuccessResponseType> state,
  ) {
    //override if needed
  }

  ///just handle execution outside
  Future<Either<SuccessResponseType, String>> handleEvent(Event event);

  @protected
  void resetCursorPaginationState() {
    totalItems = null;
    currentCursor = null;
    nextCursor = null;
    _noDataLeft = null;
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
      resetCursorPaginationState();
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
  void setCursor({CursorPaginationResponse? model}) {
    if (model == null) return;
    if (model.current != null && nextCursor == model.current) {
      currentCursor = model.current;
    }
    nextCursor = model.nextCursor;
    _noDataLeft = model.nextCursor == null;
    totalItems =
        model.total ?? totalItems; // ensure that totalItems is not null
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

  LoadingState _resolveLoadingState(Event event) {
    if (event is FetchDataWithQueryEvent && currentCursor != null) {
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
    requestCancelScope.cancelActive(reason: 'cursor pagination bloc reset');
    _lastSettledState = null;
    if (event.clearsData) {
      resetCursorPaginationState();
    }
    if (event.clearsQuery) {
      currentQuery = null;
    }
  }

  bool getIsNoPageAvailable() => (_noDataLeft ?? false);

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
    CursorDataHolder cursorPageHolder,
  ) {
    //log('id is $id and state id is ');
    final model = state.data as CursorPaginationResponse;
    if (state.hasCleared) {
      cursorPageHolder.items.clear();
    } else if (cursorPageHolder.nextCursor != model.current) {
      return;
    }
    cursorPageHolder.nextCursor = model.nextCursor;
    final list = model.data ?? [];
    cursorPageHolder.items.addAll(list);
  }

  void refresh() {
    add(
      FetchDataWithQueryEvent(clearPageWithNewData: true, query: currentQuery)
          as Event,
    );
  }

  @override
  Future<void> close() {
    requestCancelScope.close(reason: 'cursor pagination bloc closed');
    return super.close();
  }
}

class CursorDataHolder<T> {
  List<T> items = [];
  String? nextCursor;

  CursorDataHolder({List<T>? items, String? nextCursor}) {
    if (items != null) {
      this.items = items;
    }
    if (nextCursor != null) {
      this.nextCursor = nextCursor;
    }
  }

  bool get hasMore => nextCursor != null;
}
