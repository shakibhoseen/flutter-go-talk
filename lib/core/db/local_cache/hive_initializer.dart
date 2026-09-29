import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

/// Opens Hive once for the whole app.
///
/// Type adapters are **not** listed here. In the app this came from they were,
/// and core then had to import a model out of every feature that cached
/// anything. Features register their own instead ([registerAdapter]), so
/// deleting a feature deletes its adapter with it.
class HiveInitializer {
  HiveInitializer._();

  static Completer<void>? _initCompleter;

  static final List<TypeAdapter<dynamic>> _pendingAdapters = [];

  /// Registers a feature's adapter. Safe before or after [ensureInitialized]:
  /// called early it is queued, called later it goes straight to Hive. Hive
  /// ignores a typeId it already knows, so a hot restart does not throw.
  static void registerAdapter(TypeAdapter<dynamic> adapter) {
    if (_initCompleter?.isCompleted ?? false) {
      _register(adapter);
      return;
    }
    _pendingAdapters.add(adapter);
  }

  static Future<void> ensureInitialized() {
    final completer = _initCompleter;
    if (completer != null) return completer.future;

    final created = Completer<void>();
    _initCompleter = created;
    unawaited(_doInit(created));
    return created.future;
  }

  static Future<void> _doInit(Completer<void> completer) async {
    try {
      await Hive.initFlutter();
      _pendingAdapters.forEach(_register);
      _pendingAdapters.clear();
      completer.complete();
    } catch (e, st) {
      // Null it out so a later call can try again — a failed init must not
      // leave every cached read waiting on a future that never completes.
      _initCompleter = null;
      completer.completeError(e, st);
    }
  }

  static void _register(TypeAdapter<dynamic> adapter) {
    if (Hive.isAdapterRegistered(adapter.typeId)) return;
    Hive.registerAdapter(adapter);
  }
}
