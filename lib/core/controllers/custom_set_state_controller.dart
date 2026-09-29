import 'dart:ui';

class CustomSetStateController<T> {
  Function(T?)? _updateCallback;

  void setUpdateCallback(Function(T? data) callback) {
    _updateCallback = callback;
  }

  void updateData({T? data}) {
    // call actually setState for Stateful Widget
    _updateCallback?.call(data);
  }

  void clean() {
    _updateCallback = null; // ফাংশন রেফারেন্স ক্লিন করা
  }
}

class CustomVoidCallbackController {
  VoidCallback? _updateCallback;

  void bindCallback(VoidCallback callback) {
    _updateCallback = callback;
  }

  void call() {
    // call actually setState for Stateful Widget
    _updateCallback?.call();
  }

  void clean() {
    _updateCallback = null; // ফাংশন রেফারেন্স ক্লিন করা
  }
}
