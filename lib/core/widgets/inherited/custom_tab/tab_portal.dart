import 'package:flutter/material.dart' hide TabBar, TabBarView, Tab;

import 'my_tab_bar.dart';
import 'tab_controller_host.dart';

/// Consumer that builds a TabBar using the host's controller.
/// If controller is null and hideWhileRebuilding = true -> returns SizedBox.shrink().
class TabBarPortal<T> extends StatelessWidget implements PreferredSizeWidget {
  final bool isScrollable;
  final TabBarIndicatorSize? indicatorSize;
  final EdgeInsetsGeometry? labelPadding;
  final Widget Function(BuildContext context, TabController c, List<CustomTabWithValue<T>> tabs)?
  builder;

  const TabBarPortal({
    super.key,
    this.isScrollable = true,
    this.indicatorSize,
    this.labelPadding,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final host = TabControllerHost.of<T>(context);
    if (host.controller == null && host.hideWhileRebuilding) {
      return const SizedBox.shrink();
    }
    final c = host.requireController();
    if (builder != null) return builder!(context, c, host.tabs);

    return TabBar(
      controller: c,
      isScrollable: isScrollable,
      indicatorSize: indicatorSize,
      tabs: host.tabs.map((t) => Padding(
        padding: labelPadding ?? const EdgeInsets.symmetric(horizontal: 8),
        child: Tab(text: t.compare),
      )).toList(),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);
}

/// Consumer that builds a TabBarView using the host's controller.
/// Provide a `childrenBuilder` to map tabs -> pages.
class TabViewPortal<T> extends StatelessWidget {
  final List<Widget> Function(BuildContext context, List<CustomTabWithValue<T>> tabs) childrenBuilder;
  const TabViewPortal({super.key, required this.childrenBuilder});

  @override
  Widget build(BuildContext context) {
    final host = TabControllerHost.of<T>(context);
    if (host.controller == null && host.hideWhileRebuilding) {
      return const SizedBox.shrink();
    }
    final c = host.requireController();
    final children = childrenBuilder(context, host.tabs);
    assert(children.length == host.tabs.length,
    'children length must match tabs length');

    return TabBarView(
      controller: c,
      children: children,
    );
  }
}