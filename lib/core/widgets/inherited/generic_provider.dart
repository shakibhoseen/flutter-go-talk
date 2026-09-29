import 'package:flutter/material.dart';

class GenericProvider<T> extends InheritedWidget {
  const GenericProvider({super.key, required this.value, required super.child});
  final T value;

  // এটা দিয়ে easily access করব
  static T of<T>(BuildContext context, {bool listen = false}) {
    final provider = listen
        ? context.dependOnInheritedWidgetOfExactType<GenericProvider<T>>()
        : context.getInheritedWidgetOfExactType<GenericProvider<T>>();

    if (provider == null) {
      throw FlutterError(
        'GenericProvider<$T> not found in context. '
        'Make sure to wrap your widget tree with GenericProvider<$T>.',
      );
    }
    return provider.value;
  }

  @override
  bool updateShouldNotify(GenericProvider<T> oldWidget) {
    return oldWidget.value != value;
  }
}

class MultiGenericProvider extends StatelessWidget {
  const MultiGenericProvider({
    super.key,
    required this.builders,
    required this.child,
  });
  final Widget child;
  final List<InheritedWidget Function(Widget child)> builders;

  @override
  Widget build(BuildContext context) {
    return builders.fold<Widget>(
      child,
      (previous, builder) => builder(previous),
    );
  }
}

extension GenericProviderExt<T> on T {
  GenericProvider<T> provide(Widget child) =>
      GenericProvider<T>(value: this, child: child);
}
