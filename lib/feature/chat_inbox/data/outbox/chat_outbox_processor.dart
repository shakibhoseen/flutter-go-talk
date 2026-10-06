import 'dart:developer';

import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
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
class ChatOutboxProcessor {
  final LocalOutboxStorage outboxStorage;
  final ChatSocketService socketService;
  final bool Function()? isConnectedOverride;
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
    this.sendMessageOverride,
  })  : outboxStorage = outboxStorage ?? SharedPreferencesOutboxStorage(),
        socketService = socketService ?? ChatSocketService.instance;

  static final ChatOutboxProcessor instance = ChatOutboxProcessor();

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

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

  /// Processes all pending outbox messages across all conversations.
  ///
  /// Concurrency Guard: If a run is already in progress, returns immediately.
  Future<void> processPending({String? conversationIdFilter}) async {
    if (_isProcessing) {
      log('Outbox processing already running, skipping concurrent call',
          name: 'ChatOutboxProcessor');
      return;
    }

    _isProcessing = true;
    try {
      final snapshot = conversationIdFilter != null
          ? await outboxStorage.getMessagesForConversation(conversationIdFilter)
          : await outboxStorage.getAllMessages();

      if (snapshot.isEmpty) {
        return;
      }

      for (final PendingOutboxMessage item in snapshot) {
        // Stop immediately if socket disconnected
        if (!isConnected) {
          log('Socket disconnected during outbox processing, pausing retry',
              name: 'ChatOutboxProcessor');
          break;
        }

        // Re-check: has this message already been reconciled & removed by an echo?
        final stillPending =
            await outboxStorage.getMessagesForConversation(item.conversationId);
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
      _isProcessing = false;
    }
  }
}
