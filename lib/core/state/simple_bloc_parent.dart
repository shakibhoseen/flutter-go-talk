import 'common_base_bloc.dart';

/// Generic "just hit this function and show the result" bloc — attach any
/// `Future<T> Function()` (typically a repository call) via [setFunction]
/// and call [execute]. No per-feature state/event classes needed.
class SimpleBlocParent<T> extends CommonBloc<CommonEvent, CommonState, T> {
  SimpleBlocParent() : super(const InitialState());
  Future<T> Function(CommonEvent event)? _onExecute;

  void setFunction({required Future<T> Function(CommonEvent event) attach}) {
    _onExecute = attach;
  }

  @override
  Future<T> handleEvent(CommonEvent event) {
    final onExecute = _onExecute;
    if (onExecute == null) {
      throw StateError(
        'SimpleBlocParent.handleEvent called before setFunction was invoked',
      );
    }
    return onExecute(event);
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
