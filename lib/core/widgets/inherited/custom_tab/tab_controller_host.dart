import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'tab_host_scope.dart';

class TabControllerHost<T> extends StatefulWidget {
  /// Required: labels for tabs. Change list to grow/shrink tabs dynamically.
  //final List<String> tabs;

   final TabHostController<T> controller;
  final int initialIndex;

  /// When controller is being (re)built, should consumer children be hidden?
  /// If true, [TabBarPortal]/[TabViewPortal] will render SizedBox.shrink().
  final bool hideWhileRebuilding;

  /// Child subtree that can fetch the controller using [TabControllerHost.of].
  final Widget child;

  const TabControllerHost({
    super.key,
    required this.controller,
    this.initialIndex = 0,
    this.hideWhileRebuilding = true,
    required this.child,
  });

  /// Quick accessor to the nearest scope.
  static TabHostScope<T> of<T>(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<_TabInherited<T>>()
        : context.getInheritedWidgetOfExactType<_TabInherited<T>>();
    assert(scope != null, 'No TabControllerHost found in context');
    return scope!.scope;
  }

  @override
  State<TabControllerHost<T>> createState() => _TabControllerHostState<T>();
}

class _TabControllerHostState<T> extends State<TabControllerHost<T>>
    with TickerProviderStateMixin {
  TabController? _controller;
  late final ValueNotifier<bool> _ready;

  @override
  void initState() {
    super.initState();
    _ready = ValueNotifier<bool>(false);
    widget.controller.addListener(_onTabsChanged);
    _rebuildController(initial: true);
  }

  @override
  void didUpdateWidget(covariant TabControllerHost<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTabsChanged);
      widget.controller.addListener(_onTabsChanged);
      _rebuildController();
    }
    //
    // final tabsChanged =
    //     !_listEqualsDeep(oldWidget.tabs, widget.tabs); // deep compare labels
    //
    // if (tabsChanged) {
    //   _rebuildController();
    // } else {
    //   // nothing
    // }
  }

  void _onTabsChanged() => _rebuildController();

  bool _listEqualsDeep(List<String> a, List<String> b) {
    return listEquals(a, b);
  }

  void _rebuildController({bool initial = false}) {
    // Hide consumers if requested
    if (widget.hideWhileRebuilding) _ready.value = false;

    final prev = _controller;
    final oldLen = prev?.length ?? 0;
    final newLen = widget.controller.tabs.length;

    // compute next index
    final prevIndex = prev?.index ?? widget.initialIndex;
    final nextIndex = newLen == 0 ? 0 : prevIndex.clamp(0, newLen - 1);

    // dispose old *after* calculating nextIndex
    prev?.dispose();

    if (newLen == 0) {
      setState(() {
        _controller = null;
      });
      _ready.value = true; // ready, but nothing to show
      return;
    }

    final c = TabController(
      length: newLen,
      vsync: this,
      initialIndex: nextIndex,
    );

    setState(() {
      _controller = c;
    });

    _ready.value = true;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _ready.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _TabInherited<T>(
      scope: TabHostScope<T>(
        tabs: widget.controller.tabs,
        controller: _controller,
        isReady: _ready,
        hideWhileRebuilding: widget.hideWhileRebuilding,
      ),
      child: widget.child,
    );
  }
}

class _TabInherited<T> extends InheritedWidget {
  final TabHostScope<T> scope;

  const _TabInherited({
    required this.scope,
    required super.child,
  });

  @override
  bool updateShouldNotify(covariant _TabInherited<T> oldWidget) {
    // notify when controller or tabs identity changes
    return oldWidget.scope.controller != scope.controller ||
        !listEquals(oldWidget.scope.tabs, scope.tabs) ||
        oldWidget.scope.hideWhileRebuilding != scope.hideWhileRebuilding;
  }
}

class TabHostController<T> extends ChangeNotifier {
  List<CustomTabWithValue<T>> _tabs;
  String? preferredTabId; // চাইলে ID ভিত্তিক restore

  TabHostController(List<CustomTabWithValue<T>> initialTabs)
      : _tabs = List.of(initialTabs);

  List<CustomTabWithValue<T>> get tabs => List.unmodifiable(_tabs);

  void replaceTabs(List<CustomTabWithValue<T>> next) {
    if (_tabs.length == next.length &&
        _listEqualsDeep(_tabs.map((e) => e.compare).toList(),
            next.map((e) => e.compare).toList())) {
      return;
    }
    _tabs = List.of(next);
    notifyListeners(); // Host শুনে TabController recreate করবে
  }

  bool _listEqualsDeep(List<String> a, List<String> b) {
    return listEquals(a, b);
  }
}

class CustomTabWithValue<T> {
  final String compare;
  final T value;

  CustomTabWithValue({required this.compare, required this.value});
}
