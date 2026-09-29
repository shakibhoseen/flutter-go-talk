part of 'common_base_bloc.dart';

abstract class CommonState {
  const CommonState();
}

class InitialState extends CommonState {
  const InitialState();
}

enum LoadingPhase { initial, refresh, pagination, submit }

class LoadingState extends CommonState {
  final LoadingPhase phase;

  const LoadingState({this.phase = LoadingPhase.initial});

  const LoadingState.initial() : phase = LoadingPhase.initial;

  const LoadingState.refresh() : phase = LoadingPhase.refresh;

  const LoadingState.pagination() : phase = LoadingPhase.pagination;

  const LoadingState.submit() : phase = LoadingPhase.submit;

  bool get isInitial => phase == LoadingPhase.initial;

  bool get isRefresh => phase == LoadingPhase.refresh;

  bool get isPagination => phase == LoadingPhase.pagination;

  bool get isSubmit => phase == LoadingPhase.submit;
}

class SuccessState<T> extends CommonState {
  final T data;
  SuccessState(this.data);
}

class SuccessWithPaginationState<T> extends CommonState {
  final T data;
  final bool hasCleared;
  SuccessWithPaginationState({required this.data, this.hasCleared = false});
}

class ErrorState extends CommonState {
  final String _message;
  final Failure? failure;

  bool get shouldShowToUser => failure?.shouldShowToUser ?? true;
  ErrorDisplayType get displayType =>
      failure?.displayType ?? ErrorDisplayType.toast;
  bool get shouldRender =>
      shouldShowToUser &&
          _message.trim().isNotEmpty &&
          displayType != ErrorDisplayType.none;
  String get message => shouldRender ? _message : '';
  String? get visibleMessage => shouldRender ? _message : null;
  bool get shouldToast =>
      shouldRender &&
          (displayType == ErrorDisplayType.toast ||
              displayType == ErrorDisplayType.dialog);

  ErrorState(String message, {this.failure}) : _message = message;

  factory ErrorState.fromError(dynamic error) {
    final failure = ErrorHandler.resolve(error, triggerSideEffects: false);
    return ErrorState(failure.responseMessage, failure: failure);
  }

  bool get isCancellation => failure?.responseCode == ResponseCode.CANCEL;
}
