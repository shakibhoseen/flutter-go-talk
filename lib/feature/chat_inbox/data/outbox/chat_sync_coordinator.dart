import 'dart:developer';

import 'package:flutter/foundation.dart';
import '../../../../core/db/network/socket/chat_socket_event_dispatcher.dart';
import '../../../../core/db/network/socket/chat_socket_service.dart';
import '../../../../core/session/auth_session.dart';
import '../inbox_message_list_cursor_bloc.dart';
import 'chat_outbox_processor.dart';
import 'local_outbox_storage.dart';

/// Coordinates recovery when the socket reconnects or the app starts up, and
/// globally reconciles outgoing server echos even when no chat screen is mounted.
///
/// Ensures the strict recovery order:
/// 1. If an active inbox bloc is performing initial load, defers recovery until it completes.
/// 2. Runs delta sync first on the active inbox bloc (if present).
/// 3. Reconciles any server-persisted messages, removing them from the outbox.
/// 4. If delta sync fails, aborts outbox retry to prevent sending over an unstable connection.
/// 5. If delta sync succeeds (or no inbox bloc is active), processes remaining unresolved outbox messages.
/// 6. Preserves Seen ACK behavior upon successful sync.
class ChatSyncCoordinator {
  final ChatOutboxProcessor outboxProcessor;
  final ChatSocketService socketService;
  final ChatSocketEventDispatcher eventDispatcher;
  final LocalOutboxStorage outboxStorage;
  final String? Function()? currentUserIdProvider;
  final bool Function()? isConnectedOverride;

  ChatSyncCoordinator({
    ChatOutboxProcessor? outboxProcessor,
    ChatSocketService? socketService,
    ChatSocketEventDispatcher? eventDispatcher,
    LocalOutboxStorage? outboxStorage,
    this.currentUserIdProvider,
    this.isConnectedOverride,
  })  : outboxProcessor = outboxProcessor ?? ChatOutboxProcessor.instance,
        socketService = socketService ?? ChatSocketService.instance,
        eventDispatcher = eventDispatcher ?? ChatSocketEventDispatcher.instance,
        outboxStorage = outboxStorage ??
            (outboxProcessor?.outboxStorage ?? ChatOutboxProcessor.instance.outboxStorage);

  static final ChatSyncCoordinator instance = ChatSyncCoordinator();

  bool get isConnected => isConnectedOverride != null
      ? isConnectedOverride!()
      : socketService.isConnected;

  InboxMessageListCursorBloc? _activeInboxBloc;
  VoidCallback? _onSyncSuccess;

  SocketConnectionState? _lastConnectionState;
  bool _isListening = false;
  bool _isReconnecting = false;
  bool _isRecoveryPending = false;
  SocketUnsubscribe? _echoUnsubscribe;

  bool get isReconnecting => _isReconnecting;
  bool get isListening => _isListening;
  bool get isRecoveryPending => _isRecoveryPending;
  InboxMessageListCursorBloc? get activeInboxBloc => _activeInboxBloc;

  /// Starts listening to socket connection state changes and incoming message echos.
  void start() {
    if (_isListening) return;
    _isListening = true;
    _lastConnectionState = socketService.connectionState.value;
    socketService.connectionState.addListener(_handleSocketStateChange);
    _echoUnsubscribe = eventDispatcher.listen(
      eventType: 'new_message',
      callback: _handleGlobalNewMessage,
    );
  }

  /// Stops listening to socket connection state changes and message echos.
  void stop() {
    if (!_isListening) return;
    socketService.connectionState.removeListener(_handleSocketStateChange);
    _echoUnsubscribe?.call();
    _echoUnsubscribe = null;
    _isListening = false;
  }

  /// Reconciles an incoming server `new_message` globally, removing the matching outbox item
  /// if sent by the current authenticated user.
  @visibleForTesting
  Future<void> handleGlobalNewMessage(Map<String, dynamic> json) async {
    final clientMsgId = json['client_message_id']?.toString();
    if (clientMsgId == null || clientMsgId.trim().isEmpty) {
      return;
    }

    final senderId = json['sender_id']?.toString();
    final currentUserId = currentUserIdProvider != null
        ? currentUserIdProvider!()
        : AuthSession.tokens?.user?.id?.toString();

    // Only remove when the message was sent by the authenticated current user
    if (senderId != null &&
        currentUserId != null &&
        senderId == currentUserId) {
      log(
        'Global echo reconciliation: removing confirmed outbox item $clientMsgId',
        name: 'ChatSyncCoordinator',
      );
      await outboxStorage.remove(clientMsgId);
    }
  }

  void _handleGlobalNewMessage(Map<String, dynamic> json) {
    handleGlobalNewMessage(json);
  }

  /// Registers the currently active conversation screen's bloc.
  void registerActiveBloc(
    InboxMessageListCursorBloc bloc, {
    VoidCallback? onSyncSuccess,
  }) {
    _activeInboxBloc = bloc;
    _onSyncSuccess = onSyncSuccess;
    bloc.onInitialLoadCompleted = _handleInitialLoadCompleted;
  }

  /// Unregisters the active conversation screen's bloc when disposed.
  void unregisterActiveBloc(InboxMessageListCursorBloc bloc) {
    if (_activeInboxBloc == bloc) {
      _activeInboxBloc?.onInitialLoadCompleted = null;
      _activeInboxBloc = null;
      _onSyncSuccess = null;
      _isRecoveryPending = false;
    }
  }

  void _handleInitialLoadCompleted() {
    if (!_isRecoveryPending) return;
    _isRecoveryPending = false;

    if (isConnected) {
      log(
        'Initial history load completed while recovery was pending; resuming reconnect recovery',
        name: 'ChatSyncCoordinator',
      );
      handleReconnect(
        inboxBloc: _activeInboxBloc,
        onSyncSuccess: _onSyncSuccess,
      );
    }
  }

  void _handleSocketStateChange() {
    final currentState = socketService.connectionState.value;
    final wasDisconnected =
        _lastConnectionState == SocketConnectionState.reconnecting ||
            _lastConnectionState == SocketConnectionState.disconnected;
    _lastConnectionState = currentState;

    if (wasDisconnected && currentState == SocketConnectionState.connected) {
      handleReconnect(
        inboxBloc: _activeInboxBloc,
        onSyncSuccess: _onSyncSuccess,
      );
    }
  }

  /// Coordinated recovery for a reconnect event.
  ///
  /// Concurrency Guard: Prevents multiple concurrent reconnect runs across onConnected/onResume/manual calls.
  Future<bool> handleReconnect({
    InboxMessageListCursorBloc? inboxBloc,
    VoidCallback? onSyncSuccess,
  }) async {
    if (_isReconnecting) {
      log('Reconnect coordination already in progress, skipping duplicate call',
          name: 'ChatSyncCoordinator');
      return false;
    }

    _isReconnecting = true;
    try {
      final targetBloc = inboxBloc ?? _activeInboxBloc;
      final callback = onSyncSuccess ?? _onSyncSuccess;

      // 0. If active bloc is currently in initial loading state, defer recovery until completion
      if (targetBloc != null && targetBloc.isInitialLoading) {
        log(
          'Active bloc is currently performing initial load; deferring recovery until completion',
          name: 'ChatSyncCoordinator',
        );
        _isRecoveryPending = true;
        return false;
      }

      // 1. Delta sync first if an inbox bloc is active
      if (targetBloc != null) {
        log(
          'Running forward delta sync first for conversation: ${targetBloc.conversationId}',
          name: 'ChatSyncCoordinator',
        );

        final syncSuccess = await targetBloc.syncMissedMessages();
        if (!syncSuccess) {
          // If delta sync kicked off an initial load because no messages were loaded,
          // keep recovery pending until that initial load finishes.
          if (targetBloc.isInitialLoading) {
            _isRecoveryPending = true;
          }
          log(
            'Delta sync failed or incomplete, skipping outbox retry for now',
            name: 'ChatSyncCoordinator',
          );
          return false;
        }

        // 2. Delta sync succeeded: trigger Seen ACK callback
        callback?.call();
      }

      // 3. Process remaining unresolved outbox messages
      await outboxProcessor.processPending();
      return true;
    } finally {
      _isReconnecting = false;
    }
  }
}
