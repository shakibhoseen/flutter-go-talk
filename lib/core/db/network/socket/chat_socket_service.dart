import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../config/app_flavor_config.dart';
import '../../../session/auth_session.dart';
import '../network_service_type.dart';

/// Real-time chat socket, one per signed-in session — the `ws://` sibling of
/// the same backend `GlobalDataApi`/`DioSingleton` talk to
/// ([NetworkServiceType.chat]), authenticated with [AuthSession.accessToken]
/// as a query param.
///
/// Lifecycle is driven from the call sites that already know when a session
/// starts or ends (login success, startup session-restore, logout) rather
/// than watched implicitly, so "why is this connected right now" always has
/// a one-line answer.
class ChatSocketService {
  ChatSocketService._();

  static final ChatSocketService instance = ChatSocketService._();

  WebSocketChannel? _channel;
  StreamController<dynamic>? _events;

  /// Broadcast so the conversation list and an open thread can both listen
  /// without racing to be the first (and only) subscriber.
  Stream<dynamic> get messages =>
      (_events ??= StreamController<dynamic>.broadcast()).stream;

  bool get isConnected => _channel != null;

  void connect() {
    if (_channel != null) return;

    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) return;

    final channel = WebSocketChannel.connect(_socketUri(token));
    _channel = channel;

    channel.stream.listen(
      (event) => _events?.add(event),
      onError: (Object error, StackTrace stackTrace) {
        log('chat socket error: $error', name: 'ChatSocketService');
        _events?.addError(error, stackTrace);
        disconnect();
      },
      onDone: disconnect,
      cancelOnError: true,
    );
  }

  void send(Object? message) => _channel?.sink.add(message);

  /// Sends a chat message the way the Go backend's hub expects it — the
  /// server both persists it and echoes a `new_message` event back to this
  /// same socket, so the sender's own UI updates from that echo rather than
  /// from an optimistic local copy (which would otherwise double up).
  void sendMessage({
    required String conversationId,
    required String content,
    String messageType = 'text',
  }) {
    send(
      jsonEncode({
        'type': 'send_message',
        'payload': {
          'conversation_id': conversationId,
          'content': content,
          'message_type': messageType,
        },
      }),
    );
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
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
