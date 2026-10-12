import 'common_base_bloc.dart';

/// Generic "just hit this function and show the result" bloc — attach any
/// `Future<T> Function()` (typically a repository call) via [setFunction]
/// and call [execute]. No per-feature state/event classes needed.
class SimpleBlocParent<T> extends CommonBloc<CommonEvent, CommonState, T> {
  SimpleBlocParent() : super(const InitialState());
  Future<T> Function(CommonEvent event)? _onExecute;
  Stream<T> Function(CommonEvent event)? _onExecuteStream;

  void setFunction({required Future<T> Function(CommonEvent event) attach}) {
    _onExecute = attach;
    _onExecuteStream = null;
  }

  void setStreamFunction({
    required Stream<T> Function(CommonEvent event) attach,
  }) {
    _onExecuteStream = attach;
    _onExecute = null;
  }

  @override
  Stream<T> Function(CommonEvent event)? get eventStreamBuilder =>
      _onExecuteStream;

  @override
  Future<T> handleEvent(CommonEvent event) {
    final onExecute = _onExecute;
    if (onExecute != null) {
      return onExecute(event);
    }
    final onExecuteStream = _onExecuteStream;
    if (onExecuteStream != null) {
      return onExecuteStream(event).last;
    }
    throw StateError(
      'SimpleBlocParent.handleEvent called before setFunction or setStreamFunction was invoked',
    );
  }

  @override
  LoadingState resolveLoadingState(CommonEvent event) =>
      const LoadingState.submit();

  Future<void> execute() async => add(const FetchDataEvent());

  bool get isLoading => state is LoadingState;

  /// Pushes a new success value directly — for state that changes from a
  /// source other than [execute] (a websocket event updating an
  /// already-loaded list, say) without re-running the fetch.
  // `emit` is restricted to bloc's own event handlers by convention, but
  // this class *is* the bloc — a direct push is the point of this method.
  // ignore: invalid_use_of_visible_for_testing_member
  void emitSuccess(T data) => emit(SuccessState(data));
}
