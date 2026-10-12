import 'dart:async';
import 'dart:math';

import '../../../core/db/local_cache/chat_message_cache.dart';
import '../../../core/db/network/socket/chat_socket_service.dart';
import '../../../core/session/auth_session.dart';

/// Manages delivery of seen acknowledgments (`ack_seen`), ensuring that:
/// 1. Offline reads are never dropped or silently lost.
/// 2. `_lastDispatchedAckId` advances ONLY after frames are successfully written to an active socket.
/// 3. Offline reads are coalesced to the highest seen message ID.
/// 4. Pending seen intents are durably persisted in local cache, surviving app restarts.
/// 5. Strictly isolated per authenticated user session.
class ChatSeenAckManager {
  static final ChatSeenAckManager instance = ChatSeenAckManager._internal();

  factory ChatSeenAckManager({
    ChatSocketService? socketService,
    ChatMessageCache? messageCache,
    String Function()? userScopeResolver,
  }) {
    if (socketService != null ||
        messageCache != null ||
        userScopeResolver != null) {
      return ChatSeenAckManager._internal(
        socketService: socketService,
        messageCache: messageCache,
        userScopeResolver: userScopeResolver,
      );
    }
    return instance;
  }

  ChatSeenAckManager._internal({
    ChatSocketService? socketService,
    ChatMessageCache? messageCache,
    String Function()? userScopeResolver,
  })  : _socketService = socketService ?? ChatSocketService.instance,
        _messageCache = messageCache ?? ChatMessageCache(),
        _userScopeResolver = userScopeResolver ??
            (() => AuthSession.tokens?.user?.id?.toString() ?? 'guest');

  final ChatSocketService _socketService;
  final ChatMessageCache _messageCache;
  final String Function() _userScopeResolver;

  String resolveCurrentUserScope() => _userScopeResolver();

  /// Highest message ID successfully sent over the wire per conversation.
  final Map<String, int> _lastDispatchedPerConv = {};

  int getLastDispatchedAckId(String conversationId) =>
      _lastDispatchedPerConv[conversationId] ?? 0;

  /// Resets in-memory dispatched ACK tracking across all conversations (e.g. on logout or user switch).
  void reset() {
    _lastDispatchedPerConv.clear();
  }

  /// Clears in-memory session dispatch records when a new socket connection is established,
  /// allowing unconfirmed pending watermarks to be re-dispatched over the new connection.
  void onSocketReconnected() {
    _lastDispatchedPerConv.clear();
  }

  /// Records that the user viewed messages up to [messageId] in [conversationId].
  ///
  /// Always persists the latest read watermark to durable storage first.
  /// If connected, dispatches immediately across the socket and tracks dispatch in memory.
  /// Note: The pending intent is NOT deleted on local socket write (sink.add); it is only
  /// retired when the Go server authoritatively confirms watermark processing.
  Future<void> onMessageSeen({
    required String conversationId,
    required int messageId,
    required int senderId,
  }) async {
    if (messageId <= 0) return;

    final userScope = resolveCurrentUserScope();

    // 1. Durably persist / update latest read watermark on disk FIRST
    final existingPending = await _messageCache.getPendingSeenAck(
      conversationId: conversationId,
      targetUserScope: userScope,
    );

    final highestPendingId = existingPending != null
        ? max(existingPending.messageId, messageId)
        : messageId;

    await _messageCache.savePendingSeenAck(
      conversationId: conversationId,
      messageId: highestPendingId,
      senderId: senderId,
      targetUserScope: userScope,
    );

    // 2. If already dispatched in this connection session, do not duplicate
    final lastDispatched = getLastDispatchedAckId(conversationId);
    if (messageId <= lastDispatched) {
      return;
    }

    // 3. Attempt immediate dispatch if socket is connected
    if (_socketService.isConnected) {
      final sent = _socketService.sendSeenAck(
        conversationId: conversationId,
        messageId: messageId.toString(),
        senderId: senderId,
      );
      if (sent) {
        _lastDispatchedPerConv[conversationId] =
            max(_lastDispatchedPerConv[conversationId] ?? 0, messageId);
      }
    }
  }

  /// Retires a pending seen intent from disk once the server has authoritatively
  /// confirmed that the user's read watermark in PostgreSQL is at or beyond [serverMessageId].
  Future<void> confirmServerWatermark({
    required String conversationId,
    required int serverMessageId,
  }) async {
    if (serverMessageId <= 0) return;
    final userScope = resolveCurrentUserScope();
    final pending = await _messageCache.getPendingSeenAck(
      conversationId: conversationId,
      targetUserScope: userScope,
    );
    if (pending != null && serverMessageId >= pending.messageId) {
      await _messageCache.clearPendingSeenAck(
        conversationId: conversationId,
        upToMessageId: serverMessageId,
        targetUserScope: userScope,
      );
    }
  }

  /// Retries all pending seen ACKs across all conversations (or a specific conversation).
  ///
  /// Dispatches unconfirmed pending ACKs across an active socket connection.
  /// Updates `_lastDispatchedAckId` in memory to prevent duplicate dispatches on the same connection.
  Future<bool> retryPendingAcks({String? conversationId}) async {
    if (!_socketService.isConnected) {
      return false;
    }

    final userScope = resolveCurrentUserScope();

    try {
      if (conversationId != null) {
        final pending = await _messageCache.getPendingSeenAck(
          conversationId: conversationId,
          targetUserScope: userScope,
        );
        if (pending != null &&
            pending.messageId > getLastDispatchedAckId(conversationId)) {
          final sent = _socketService.sendSeenAck(
            conversationId: conversationId,
            messageId: pending.messageId.toString(),
            senderId: pending.senderId,
          );
          if (sent) {
            _lastDispatchedPerConv[conversationId] =
                max(_lastDispatchedPerConv[conversationId] ?? 0, pending.messageId);
          }
        }
        return true;
      }

      final allPending = await _messageCache.getAllPendingSeenAcks(
        targetUserScope: userScope,
      );

      for (final entry in allPending.entries) {
        final convId = entry.key;
        final pending = entry.value;

        if (pending.messageId > getLastDispatchedAckId(convId)) {
          final sent = _socketService.sendSeenAck(
            conversationId: convId,
            messageId: pending.messageId.toString(),
            senderId: pending.senderId,
          );
          if (sent) {
            _lastDispatchedPerConv[convId] =
                max(_lastDispatchedPerConv[convId] ?? 0, pending.messageId);
          }
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }
}
