import 'package:flutter/material.dart';

import '../navigation/navigation_service.dart';

/// Base for screens that need to pause/resume something (video playback, a
/// timer, an animation) when another screen is pushed on top of them, and
/// resume it when they come back into view — without every such screen
/// wiring up `RouteAware` subscription/unsubscription by hand.
///
/// Override [setController] with the [ScreenVisibleController]s this screen
/// owns; they get stopped on [didPushNext] (something else was pushed over
/// this screen) and started again on [didPopNext] (back to this screen).
///
/// Requires [NavigationService.routeObserver] to be registered in
/// `MaterialApp.navigatorObservers`.
abstract class RouteAwareState<T extends StatefulWidget> extends State<T>
    with RouteAware {
  bool _isSubscribed = false;

  @override
  void initState() {
    super.initState();
    _addControllers(setController());
    // Subscribing needs to happen after this screen's own route exists.
    // `NavigationService.observer.currentRoute` (tracked via the app-wide
    // NavigatorObserver) is used instead of `ModalRoute.of(context)` here —
    // that also works and is the more common approach, but doing it via
    // the tracked current route avoids relying on inherited-widget timing
    // in `didChangeDependencies`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = NavigationService.observer.currentRoute;
      if (route is PageRoute && !_isSubscribed) {
        NavigationService.routeObserver.subscribe(this, route);
        _isSubscribed = true;
      }
    });
  }

  @override
  void dispose() {
    if (_isSubscribed) {
      NavigationService.routeObserver.unsubscribe(this);
    }
    super.dispose();
  }

  @override
  void didPopNext() => _startControllers();

  @override
  void didPushNext() => _stopControllers();

  @override
  void didPush() {}

  final List<ScreenVisibleController> _controllers =
      <ScreenVisibleController>[];

  void _stopControllers() {
    for (final controller in _controllers) {
      controller.stop();
    }
  }

  void _startControllers() {
    for (final controller in _controllers) {
      controller.start();
    }
  }

  /// Override to declare the controllers this screen should pause/resume.
  List<ScreenVisibleController> setController() => const [];

  void _addControllers(List<ScreenVisibleController> controllers) {
    _controllers
      ..clear()
      ..addAll(controllers);
  }
}

/// A start/stop callback pair bound to a [BuildContext], guarded so it never
/// fires after that context is unmounted (e.g. the screen was disposed
/// between the route-visibility change and the callback running).
class ScreenVisibleController {
  VoidCallback? _startCallback;
  VoidCallback? _stopCallback;
  BuildContext? _context;

  void bind({
    required BuildContext context,
    required VoidCallback start,
    required VoidCallback stop,
  }) {
    _context = context;
    _startCallback = start;
    _stopCallback = stop;
  }

  void start() {
    final context = _context;
    if (context != null && context.mounted) _startCallback?.call();
  }

  void stop() {
    final context = _context;
    if (context != null && context.mounted) _stopCallback?.call();
  }
}
