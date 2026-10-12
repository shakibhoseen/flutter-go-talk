import 'dart:developer';

import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'local_outbox_storage.dart';
import 'pending_outbox_message.dart';

/// Dedicated processor responsible for retrying unresolved outgoing outbox messages.
///
/// Core invariants:
/// 1. Reuses the exact original [clientMessageId] across all retries.
/// 2. Retains outbox items upon transmission (they are removed strictly via server confirmation).
/// 3. Halts immediately if the socket is or becomes disconnected.
/// 4. Guards against concurrent processing runs.
/// 5. Validates each item is still present in the outbox before transmitting (to skip items
///    reconciled by an echo or delta sync while processing).
/// 6. Strictly isolates outbox retries to the active authenticated user, halting on account switch or logout.
class ChatOutboxProcessor {
  final LocalOutboxStorage outboxStorage;
  final ChatSocketService socketService;
  final bool Function()? isConnectedOverride;
  final String Function()? currentUserScopeProvider;
  final void Function({
    required String conversationId,
    required String content,
    required String clientMessageId,
    String messageType,
  })? sendMessageOverride;

  ChatOutboxProcessor({
    LocalOutboxStorage? outboxStorage,
    ChatSocketService? socketService,
    this.isConnectedOverride,
    this.currentUserScopeProvider,
    this.sendMessageOverride,
  })  : outboxStorage = outboxStorage ?? SharedPreferencesOutboxStorage(),
        socketService = socketService ?? ChatSocketService.instance;

  static final ChatOutboxProcessor instance = ChatOutboxProcessor();

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  int _runToken = 0;

  /// Halts any in-flight processing run immediately (e.g. on logout or account switch).
  void cancel() {
    _runToken++;
    _isProcessing = false;
  }

  String _resolveCurrentUserScope() {
    if (currentUserScopeProvider != null) {
      return currentUserScopeProvider!();
    }
    final user = AuthSession.tokens?.user;
    if (user != null && user.id != null && user.id! > 0) {
      return user.id.toString();
    }
    return 'guest';
  }

  bool get isConnected => isConnectedOverride != null
      ? isConnectedOverride!()
      : socketService.isConnected;

  void sendMessage({
    required String conversationId,
    required String content,
    required String clientMessageId,
    String messageType = 'text',
  }) {
    if (sendMessageOverride != null) {
      sendMessageOverride!(
        conversationId: conversationId,
        content: content,
        clientMessageId: clientMessageId,
        messageType: messageType,
      );
    } else {
      socketService.sendMessage(
        conversationId: conversationId,
        content: content,
        clientMessageId: clientMessageId,
        messageType: messageType,
      );
    }
  }

  /// Processes all pending outbox messages across all conversations for the active user.
  ///
  /// Concurrency Guard: If a run is already in progress, returns immediately.
  Future<void> processPending({
    String? conversationIdFilter,
    String? targetUserScope,
  }) async {
    if (_isProcessing) {
      log('Outbox processing already running, skipping concurrent call',
          name: 'ChatOutboxProcessor');
      return;
    }

    _isProcessing = true;
    final runToken = ++_runToken;
    try {
      final activeUser = targetUserScope ?? _resolveCurrentUserScope();
      final snapshot = conversationIdFilter != null
          ? await outboxStorage.getMessagesForConversation(
              conversationIdFilter,
              targetUserScope: activeUser,
            )
          : await outboxStorage.getAllMessages(
              targetUserScope: activeUser,
            );

      // Guard after initial storage await
      if (_runToken != runToken) {
        log('Outbox processing was cancelled or superseded during initial fetch, aborting run',
            name: 'ChatOutboxProcessor');
        return;
      }
      if (!isConnected) {
        log('Socket disconnected during initial fetch, pausing retry',
            name: 'ChatOutboxProcessor');
        return;
      }
      final refreshedActiveUser = targetUserScope ?? _resolveCurrentUserScope();
      if (activeUser != refreshedActiveUser) {
        log(
          'Session changed during initial fetch ($activeUser != $refreshedActiveUser), halting retry',
          name: 'ChatOutboxProcessor',
        );
        return;
      }

      if (snapshot.isEmpty) {
        return;
      }

      for (final PendingOutboxMessage item in snapshot) {
        // Stop immediately if processor was cancelled
        if (_runToken != runToken) {
          log('Outbox processing was cancelled or superseded, aborting run',
              name: 'ChatOutboxProcessor');
          break;
        }

        // Stop immediately if socket disconnected
        if (!isConnected) {
          log('Socket disconnected during outbox processing, pausing retry',
              name: 'ChatOutboxProcessor');
          break;
        }

        // Guard against session change / account switch during async loop
        final currentActiveUser = targetUserScope ?? _resolveCurrentUserScope();
        if (item.senderId.isNotEmpty && item.senderId != currentActiveUser) {
          log(
            'Session changed during outbox processing (${item.senderId} != $currentActiveUser), halting retry',
            name: 'ChatOutboxProcessor',
          );
          break;
        }

        // Re-check: has this message already been reconciled & removed by an echo?
        final stillPending = await outboxStorage.getMessagesForConversation(
          item.conversationId,
          targetUserScope: currentActiveUser,
        );

        // Guard after in-loop storage await: re-check run token, socket connection, and session
        if (_runToken != runToken) {
          log('Outbox processing was cancelled or superseded during await, aborting run',
              name: 'ChatOutboxProcessor');
          break;
        }

        if (!isConnected) {
          log('Socket disconnected during await in outbox processing, pausing retry',
              name: 'ChatOutboxProcessor');
          break;
        }

        final postAwaitActiveUser = targetUserScope ?? _resolveCurrentUserScope();
        if (item.senderId.isNotEmpty && item.senderId != postAwaitActiveUser) {
          log(
            'Session changed during await in outbox processing (${item.senderId} != $postAwaitActiveUser), halting retry',
            name: 'ChatOutboxProcessor',
          );
          break;
        }

        final exists =
            stillPending.any((m) => m.clientMessageId == item.clientMessageId);
        if (!exists) {
          log(
            'Outbox message ${item.clientMessageId} was already reconciled, skipping send',
            name: 'ChatOutboxProcessor',
          );
          continue;
        }

        try {
          sendMessage(
            conversationId: item.conversationId,
            content: item.content,
            clientMessageId: item.clientMessageId,
            messageType: item.messageType,
          );
        } catch (e) {
          log('Error sending outbox message ${item.clientMessageId}: $e',
              name: 'ChatOutboxProcessor');
        }
      }
    } finally {
      if (_runToken == runToken) {
        _isProcessing = false;
      }
    }
  }
}
