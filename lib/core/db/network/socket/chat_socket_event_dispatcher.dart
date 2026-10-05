import 'dart:async';
import 'dart:developer';

import 'socket_event.dart';
import 'chat_socket_service.dart';

typedef SocketUnsubscribe = void Function();

class ChatSocketEventDispatcher {
  ChatSocketEventDispatcher._();

  static final ChatSocketEventDispatcher instance =
  ChatSocketEventDispatcher._();

  final ChatSocketService _socket =
      ChatSocketService.instance;

  final Map<String, List<_SocketListener>> _listeners = {};

  StreamSubscription<dynamic>? _socketSubscription;

  bool _started = false;

  void start() {
    if (_started) return;

    _started = true;

    _socketSubscription =
        _socket.messages.listen(_handleRawMessage);
  }

  void _handleRawMessage(dynamic raw) {
    log(
      'raw socket data: $raw',
      name: 'ChatSocketDispatcher',
    );

    final events = decodeSocketEvents(raw);

    for (final event in events) {
      _dispatch(event);
    }
  }

  void _dispatch(Map<String, dynamic> event) {
    final type = event['type'];

    if (type is! String || type.isEmpty) {
      return;
    }

    final listeners = _listeners[type];

    if (listeners == null || listeners.isEmpty) {
      return;
    }

    for (final listener in List.of(listeners)) {
      listener.handle(event);
    }
  }

  SocketUnsubscribe listen({
    required String eventType,
    String? conversationId,
    required SocketEventCallback callback,
  }) {
    start();

    final listener = _SocketListener(
      conversationId: conversationId,
      callback: callback,
    );

    _listeners
        .putIfAbsent(eventType, () => [])
        .add(listener);

    return () {
      final listeners = _listeners[eventType];

      if (listeners == null) return;

      listeners.remove(listener);

      if (listeners.isEmpty) {
        _listeners.remove(eventType);
      }
    };
  }

  void dispose() {
    _socketSubscription?.cancel();
    _socketSubscription = null;

    _listeners.clear();

    _started = false;
  }
}

class _SocketListener {
  final String? conversationId;
  final SocketEventCallback callback;

  _SocketListener({
    required this.conversationId,
    required this.callback,
  });

  void handle(Map<String, dynamic> event) {
    final payload = event['payload'];

    if (payload is! Map) {
      return;
    }

    final json = Map<String, dynamic>.from(payload);

    if (conversationId != null &&
        json['conversation_id']?.toString() !=
            conversationId) {
      return;
    }

    callback(json);
  }
}