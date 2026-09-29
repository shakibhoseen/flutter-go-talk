import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'tab_controller_host.dart';

/// Read-only scope you can keep if you want manual access.
class TabHostScope<T> {
  final List<CustomTabWithValue<T>> tabs;
  final TabController? controller;
  final ValueListenable<bool> isReady;
  final bool hideWhileRebuilding;

  TabHostScope({
    required this.tabs,
    required this.controller,
    required this.isReady,
    required this.hideWhileRebuilding,
  });

  /// Throws if controller is null.
  TabController requireController() {
    final c = controller;
    assert(c != null, 'TabController is not ready yet.');
    return c!;
  }
}