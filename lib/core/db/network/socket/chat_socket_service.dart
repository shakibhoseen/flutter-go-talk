import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../config/app_flavor_config.dart';
import '../../../session/auth_session.dart';
import '../network_service_type.dart';

import 'chat_socket_event_dispatcher.dart';

enum SocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Real-time chat socket, one per signed-in session — the `ws://` sibling of
/// the same backend `GlobalDataApi`/`DioSingleton` talk to
/// ([NetworkServiceType.chat]), authenticated with [AuthSession.accessToken]
/// as a query param.
///
/// Features:
/// - Exponential backoff auto-reconnect on unexpected disconnect / error / network loss.
/// - Immediate reconnection when app resumes from background ([WidgetsBindingObserver]).
/// - [SocketConnectionState] notifier for UI connection status awareness.
class ChatSocketService with WidgetsBindingObserver {
  ChatSocketService._();

  static final ChatSocketService instance = ChatSocketService._();

  WebSocketChannel? _channel;
  StreamController<dynamic>? _events;

  final ValueNotifier<SocketConnectionState> connectionState =
      ValueNotifier(SocketConnectionState.disconnected);

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isExplicitlyDisconnected = false;
  bool _observerRegistered = false;

  /// Broadcast so the conversation list and an open thread can both listen
  /// without racing to be the first (and only) subscriber.
  Stream<dynamic> get messages =>
      (_events ??= StreamController<dynamic>.broadcast()).stream;

  bool get isConnected =>
      connectionState.value == SocketConnectionState.connected && _channel != null;

  void _ensureObserverRegistered() {
    if (_observerRegistered) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    } catch (_) {
      // Binding not initialized yet
    }
  }

  void connect() {
    _ensureObserverRegistered();
    _isExplicitlyDisconnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (_channel != null ||
        connectionState.value == SocketConnectionState.connecting) {
      return;
    }

    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      connectionState.value = SocketConnectionState.disconnected;
      return;
    }

    connectionState.value = _reconnectAttempts > 0
        ? SocketConnectionState.reconnecting
        : SocketConnectionState.connecting;

    try {
      final uri = _socketUri(token);
      log('Connecting chat socket to $uri (attempt $_reconnectAttempts)',
          name: 'ChatSocketService');

      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      channel.ready.then((_) {
        log('Chat socket connected successfully', name: 'ChatSocketService');
        _reconnectAttempts = 0;
        connectionState.value = SocketConnectionState.connected;
        ChatSocketEventDispatcher.instance.start();
      }).catchError((Object error) {
        log('Chat socket failed to connect: $error', name: 'ChatSocketService');
        _handleDisconnect();
      });

      channel.stream.listen(
        (event) {
          if (connectionState.value != SocketConnectionState.connected) {
            _reconnectAttempts = 0;
            connectionState.value = SocketConnectionState.connected;
          }
          _events?.add(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          log('Chat socket error: $error', name: 'ChatSocketService');
          _events?.addError(error, stackTrace);
          _handleDisconnect();
        },
        onDone: () {
          log('Chat socket connection closed by remote/network',
              name: 'ChatSocketService');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      log('Socket connection exception: $e', name: 'ChatSocketService');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (_channel == null &&
        connectionState.value == SocketConnectionState.disconnected &&
        _reconnectTimer?.isActive == true) {
      return;
    }

    _channel?.sink.close();
    _channel = null;

    if (_isExplicitlyDisconnected) {
      connectionState.value = SocketConnectionState.disconnected;
      return;
    }

    connectionState.value = SocketConnectionState.disconnected;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_isExplicitlyDisconnected || _reconnectTimer?.isActive == true) return;

    // Exponential backoff: 1s, 2s, 4s, 8s, max 16s
    final delaySeconds = (1 << _reconnectAttempts).clamp(1, 16);
    _reconnectAttempts++;

    connectionState.value = SocketConnectionState.reconnecting;

    log(
      'Scheduling socket reconnect in ${delaySeconds}s (attempt $_reconnectAttempts)',
      name: 'ChatSocketService',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimer = null;
      connect();
    });
  }

  void send(Object? message) {
    if (_channel == null) {
      log('Socket is disconnected, message dropped: $message',
          name: 'ChatSocketService');
      if (!_isExplicitlyDisconnected) {
        connect();
      }
      return;
    }
    _channel?.sink.add(message);
  }

  void sendRaw(Map<String, dynamic> data) => send(jsonEncode(data));

  /// Sends a chat message the way the Go backend's hub expects it — the
  /// server both persists it and echoes a `new_message` event back to this
  /// same socket, so the sender's own UI updates from that echo rather than
  /// from an optimistic local copy (which would otherwise double up).
  void sendMessage({
    required String conversationId,
    required String content,
    required String clientMessageId,
    String messageType = 'text',
  }) {
    send(
      jsonEncode({
        'type': 'send_message',
        'payload': {
          'conversation_id': conversationId,
          'content': content,
          'message_type': messageType,
          'client_message_id': clientMessageId,
        },
      }),
    );
  }

  /// Sends a seen acknowledgment (`ack_seen`) via WebSocket for instant blue ticks
  /// following industry-standard WhatsApp/Telegram real-time patterns.
  void sendDeliveredAck({
    required String conversationId,
    required String messageId,
    int senderId = 0,
  }) {
    send(
      jsonEncode({
        'type': 'ack_delivered',
        'payload': {
          'conversation_id': conversationId,
          'message_id': int.tryParse(messageId) ?? messageId,
          'sender_id': senderId,
        },
      }),
    );
  }

  void sendSeenAck({
    required String conversationId,
    required String messageId,
    int senderId = 0,
  }) {
    send(
      jsonEncode({
        'type': 'ack_seen',
        'payload': {
          'conversation_id': conversationId,
          'message_id': int.tryParse(messageId) ?? messageId,
          'sender_id': senderId,
        },
      }),
    );
  }

  /// Explicit disconnect (e.g. user logs out). Stops auto-reconnect loop.
  void disconnect() {
    _isExplicitlyDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _channel?.sink.close();
    _channel = null;
    connectionState.value = SocketConnectionState.disconnected;
  }

  /// Lifecycle listener: when user resumes app from background, reconnect immediately.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_isExplicitlyDisconnected && !isConnected) {
        log('App resumed from background, reconnecting socket immediately',
            name: 'ChatSocketService');
        connect();
      }
    }
  }

  Uri _socketUri(String token) {
    final base = Uri.parse(AppFlavorConfig.baseUrlFor(NetworkServiceType.chat));
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: _resolveHost(base.host),
      path: '/ws',
      queryParameters: {'token': token},
    );
  }

  /// `localhost`/`127.0.0.1` in the configured base url means "the
  /// developer's own machine" — that reaches an iOS simulator directly, but
  /// an Android emulator has its own loopback and needs this documented
  /// alias instead. Testing from a real device needs the Mac's LAN IP,
  /// which doesn't have a fixed alias — set it via `CHAT_BASE_URL_PROD`/
  /// `_QA` in `.env`, or the debug base-url override on the login screen.
  String _resolveHost(String host) {
    if (host != 'localhost' && host != '127.0.0.1') return host;
    if (!kIsWeb && Platform.isAndroid) return '10.0.2.2';
    return host;
  }
}
