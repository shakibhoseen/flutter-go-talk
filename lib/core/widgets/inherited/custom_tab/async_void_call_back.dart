import 'dart:async';

class AsyncVoidCallbackController {
  FutureOr<void> Function()? _callback;

  void bind(FutureOr<void> Function() cb) => _callback = cb;

  /// Always await this; if bound callback is sync, it returns immediately.
  Future<void> call() async {
    final cb = _callback;
    if (cb != null) {
      await cb(); // Works for both sync and async (FutureOr)
    }
  }

  void clean() => _callback = null;
}
