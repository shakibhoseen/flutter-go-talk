import 'dart:async';

import 'package:dio/dio.dart';

final class RequestTokenLease {
  RequestTokenLease._(this.token, this._onComplete);

  final CancelToken token;
  final void Function(CancelToken token) _onComplete;
  bool _completed = false;

  void complete() {
    if (_completed) {
      return;
    }
    _completed = true;
    _onComplete(token);
  }
}

final class RequestCancelScope {
  RequestCancelScope({String? debugLabel}) : _debugLabel = debugLabel;

  static final Object _zoneKey = Object();

  final String? _debugLabel;
  final Set<CancelToken> _activeTokens = <CancelToken>{};
  bool _closed = false;

  static RequestCancelScope? get current {
    final value = Zone.current[_zoneKey];
    return value is RequestCancelScope ? value : null;
  }

  Future<T> run<T>(Future<T> Function() action) {
    return runZoned(action, zoneValues: {_zoneKey: this});
  }

  RequestTokenLease createTokenLease() {
    final token = CancelToken();
    if (_closed) {
      token.cancel(_cancelReason('scope already closed'));
      return RequestTokenLease._(token, (_) {});
    }

    _activeTokens.add(token);
    return RequestTokenLease._(token, _activeTokens.remove);
  }

  void cancelActive({String? reason}) {
    if (_activeTokens.isEmpty) {
      return;
    }

    final cancelReason = _cancelReason(reason ?? 'request scope disposed');
    for (final token in _activeTokens.toList()) {
      if (!token.isCancelled) {
        token.cancel(cancelReason);
      }
    }
    _activeTokens.clear();
  }

  void close({String? reason}) {
    if (_closed) {
      return;
    }
    _closed = true;
    cancelActive(reason: reason);
  }

  String _cancelReason(String reason) {
    final label = _debugLabel?.trim();
    if (label == null || label.isEmpty) {
      return reason;
    }
    return '$label: $reason';
  }
}
