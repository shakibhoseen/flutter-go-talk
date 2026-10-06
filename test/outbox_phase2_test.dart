import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/local_outbox_storage.dart';
import 'package:whatsapp_flutter_go/feature/home/data/http_chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';

class MockDeltaRepoForPhase2 extends HttpChatRepository {
  final List<ChatMessage> deltaMessages;

  MockDeltaRepoForPhase2(this.deltaMessages);

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  }) async {
    return CursorPaginationResponse(
      current: sinceId?.toString(),
      data: deltaMessages,
      fromJsonFactory: ChatMessage.fromJson,
      toJsonFactory: (m) => m.toJson(),
      hasMore: false,
      nextSinceId: deltaMessages.isNotEmpty
          ? int.tryParse(deltaMessages.last.id)
          : sinceId,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 2: Outgoing Message Flow & Outbox Invariants', () {
    test('sendOutgoingMessage persists outbox BEFORE socket transmission and adds optimistic message', () async {
      final outbox = InMemoryOutboxStorage();
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-10',
        outboxStorage: outbox,
      );

      final optimisticMsg = await bloc.sendOutgoingMessage(
        content: 'Hello durable outbox',
        clientMessageId: 'uuid-flow-1',
        currentUserId: 'me-1',
      );

      // Verify optimistic message properties
      expect(optimisticMsg.id, equals(''),
          reason: 'Authoritative server ID must remain empty for optimistic messages');
      expect(optimisticMsg.clientMessageId, equals('uuid-flow-1'));
      expect(optimisticMsg.isMine, isTrue);
      expect(optimisticMsg.message, equals('Hello durable outbox'));

      // Verify message is in local bloc items list
      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.clientMessageId, equals('uuid-flow-1'));

      // Verify outbox persisted record exists
      final pendingList = await outbox.getMessagesForConversation('conv-10');
      expect(pendingList.length, equals(1));
      expect(pendingList.first.clientMessageId, equals('uuid-flow-1'));
      expect(pendingList.first.content, equals('Hello durable outbox'));

      // Outbox must NOT be removed simply on send()
      expect(pendingList.isNotEmpty, isTrue);

      bloc.close();
    });

    test('socket disconnected does not remove outbox and keeps message pending', () async {
      final outbox = InMemoryOutboxStorage();
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-offline',
        outboxStorage: outbox,
      );

      await bloc.sendOutgoingMessage(
        content: 'Offline message',
        clientMessageId: 'uuid-offline-1',
        currentUserId: 'me-1',
      );

      // Optimistic message remains in UI list
      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.id, equals(''));

      // Durable outbox remains stored
      final pending = await outbox.getMessagesForConversation('conv-offline');
      expect(pending.length, equals(1));
      expect(pending.first.clientMessageId, equals('uuid-offline-1'));

      bloc.close();
    });
  });

  group('Phase 2: Test A — Optimistic → Live WebSocket Echo Reconciliation', () {
    test('reconciles optimistic message in-place and removes outbox record upon server echo', () async {
      final outbox = InMemoryOutboxStorage();
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-10',
        outboxStorage: outbox,
      );

      const clientMsgId = 'uuid-test-a';

      // 1. Create optimistic local message
      await bloc.sendOutgoingMessage(
        content: 'Live echo test',
        clientMessageId: clientMsgId,
        currentUserId: 'user-1',
      );

      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.id, equals(''));
      expect(bloc.cursorPageHolder.items.first.clientMessageId, equals(clientMsgId));
      expect((await outbox.getAllMessages()).length, equals(1));

      // 2. Receive live server echo (id = 501, client_message_id = clientMsgId)
      final serverEcho = ChatMessage(
        id: '501',
        clientMessageId: clientMsgId,
        senderId: 'user-1',
        receiverId: 'conv-10',
        message: 'Live echo test',
        sentAt: DateTime.utc(2026, 10, 6, 12, 0, 0),
        isMine: true,
        isDelivered: true,
        isSeen: false,
      );

      await bloc.handleNewMessage(message: serverEcho);

      // 3. Assert: Exactly one message exists locally, updated with server ID 501
      expect(bloc.cursorPageHolder.items.length, equals(1),
          reason: 'Echo must reconcile in-place without duplicating the message');

      final reconciled = bloc.cursorPageHolder.items.first;
      expect(reconciled.id, equals('501'));
      expect(reconciled.clientMessageId, equals(clientMsgId));
      expect(reconciled.isDelivered, isTrue);

      // 4. Assert: Outbox record removed
      final remainingOutbox = await outbox.getAllMessages();
      expect(remainingOutbox.isEmpty, isTrue,
          reason: 'Outbox record must be removed after authoritative server confirmation');

      bloc.close();
    });
  });

  group('Phase 2: Test B — Optimistic → Delta Sync Reconciliation', () {
    test('reconciles optimistic message during delta sync and removes outbox record', () async {
      const clientMsgId = 'uuid-test-b';
      final outbox = InMemoryOutboxStorage();

      // Backend delta sync will return message 501 matching clientMsgId
      final deltaMsg = ChatMessage(
        id: '501',
        clientMessageId: clientMsgId,
        senderId: 'user-1',
        receiverId: 'conv-10',
        message: 'Delta sync message',
        sentAt: DateTime.utc(2026, 10, 6, 12, 0, 0),
        isMine: true,
        isDelivered: true,
      );

      final repo = MockDeltaRepoForPhase2([deltaMsg]);
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-10',
        repository: repo,
        outboxStorage: outbox,
      );

      // Pre-seed an older acknowledged baseline message so latestMessageId == 480
      final baselineMsg = ChatMessage(
        id: '480',
        receiverId: 'conv-10',
        senderId: 'user-2',
        message: 'Older message',
        sentAt: DateTime.utc(2026, 10, 6, 11, 0, 0),
        isMine: false,
      );
      bloc.upsertLocalItem(baselineMsg, emitState: false);

      // 1. User sends message while connection is flaky
      await bloc.sendOutgoingMessage(
        content: 'Delta sync message',
        clientMessageId: clientMsgId,
        currentUserId: 'user-1',
      );

      expect(bloc.cursorPageHolder.items.length, equals(2));
      expect((await outbox.getAllMessages()).length, equals(1));
      expect(bloc.latestMessageId, equals(480),
          reason: 'latestMessageId must ignore optimistic messages with empty id');

      // 2. Reconnect triggers delta sync
      final syncSuccess = await bloc.syncMissedMessages();
      expect(syncSuccess, isTrue);

      // 3. Assert: Exactly 2 messages locally (baseline + reconciled, NO duplicate)
      expect(bloc.cursorPageHolder.items.length, equals(2),
          reason: 'Delta sync must reconcile optimistic message in-place without duplicating');

      // Newest message (index 0) must be the reconciled message with server ID 501
      final reconciled = bloc.cursorPageHolder.items.firstWhere(
        (m) => m.clientMessageId == clientMsgId,
      );
      expect(reconciled.id, equals('501'));
      expect(reconciled.clientMessageId, equals(clientMsgId));
      expect(reconciled.isDelivered, isTrue);

      // 4. Assert: Outbox record removed
      final remainingOutbox = await outbox.getAllMessages();
      expect(remainingOutbox.isEmpty, isTrue,
          reason: 'Outbox record must be removed after delta-sync confirmation');

      bloc.close();
    });
  });

  group('Phase 2: Test C — Incoming Message from Other User Must Not Remove Unrelated Outbox', () {
    test('incoming message with different clientMessageId does not remove our outbox record', () async {
      final outbox = InMemoryOutboxStorage();
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-10',
        outboxStorage: outbox,
      );

      const ourClientMsgId = 'uuid-our-message-X';

      // 1. We have our own pending message in outbox and local list
      await bloc.sendOutgoingMessage(
        content: 'Our pending outgoing text',
        clientMessageId: ourClientMsgId,
        currentUserId: 'user-1',
      );

      expect((await outbox.getAllMessages()).length, equals(1));
      expect(bloc.cursorPageHolder.items.length, equals(1));

      // 2. Incoming message arrives from user-2 with clientMessageId = 'uuid-other-user-Y' and isMine = false
      final incomingBobMessage = ChatMessage(
        id: '600',
        clientMessageId: 'uuid-other-user-Y',
        senderId: 'user-2',
        receiverId: 'conv-10',
        message: 'Message from Bob',
        sentAt: DateTime.utc(2026, 10, 6, 12, 1, 0),
        isMine: false,
      );

      await bloc.handleNewMessage(message: incomingBobMessage);

      // 3. Assert: Our outbox record still exists completely intact!
      final outboxMessages = await outbox.getAllMessages();
      expect(outboxMessages.length, equals(1));
      expect(outboxMessages.first.clientMessageId, equals(ourClientMsgId));

      // 4. Assert: Both messages exist locally
      expect(bloc.cursorPageHolder.items.length, equals(2));
      final bobMsgInList = bloc.cursorPageHolder.items.firstWhere((m) => m.id == '600');
      expect(bobMsgInList.message, equals('Message from Bob'));
      expect(bobMsgInList.clientMessageId, equals('uuid-other-user-Y'));

      final ourMsgInList = bloc.cursorPageHolder.items.firstWhere(
        (m) => m.clientMessageId == ourClientMsgId,
      );
      expect(ourMsgInList.id, equals(''));

      bloc.close();
    });

    test('incoming message with null clientMessageId does not affect our outbox', () async {
      final outbox = InMemoryOutboxStorage();
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-10',
        outboxStorage: outbox,
      );

      const ourClientMsgId = 'uuid-our-message-Z';

      await bloc.sendOutgoingMessage(
        content: 'Our pending text',
        clientMessageId: ourClientMsgId,
        currentUserId: 'user-1',
      );

      final legacyMessage = ChatMessage(
        id: '601',
        senderId: 'user-2',
        receiverId: 'conv-10',
        message: 'Legacy incoming message without client ID',
        sentAt: DateTime.utc(2026, 10, 6, 12, 2, 0),
        isMine: false,
      );

      await bloc.handleNewMessage(message: legacyMessage);

      final outboxMessages = await outbox.getAllMessages();
      expect(outboxMessages.length, equals(1));
      expect(outboxMessages.first.clientMessageId, equals(ourClientMsgId));

      expect(bloc.cursorPageHolder.items.length, equals(2));

      bloc.close();
    });
  });

  group('Phase 2: SharedPreferencesOutboxStorage integration with Bloc', () {
    test('reconcileServerMessage removes pending item from SharedPreferencesOutboxStorage', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = SharedPreferencesOutboxStorage(prefs);
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-sp',
        outboxStorage: storage,
      );

      await bloc.sendOutgoingMessage(
        content: 'Testing SharedPreferences outbox',
        clientMessageId: 'sp-uuid-1',
        currentUserId: 'user-1',
      );

      // Verify stored in SharedPreferences
      var pending = await storage.getMessagesForConversation('conv-sp');
      expect(pending.length, equals(1));
      expect(pending.first.clientMessageId, equals('sp-uuid-1'));

      // Reconcile via server confirmation
      await bloc.reconcileServerMessage(
        ChatMessage(
          id: '800',
          clientMessageId: 'sp-uuid-1',
          senderId: 'user-1',
          receiverId: 'conv-sp',
          message: 'Testing SharedPreferences outbox',
          sentAt: DateTime.now(),
          isMine: true,
        ),
      );

      // Verify removed from SharedPreferences
      pending = await storage.getMessagesForConversation('conv-sp');
      expect(pending.isEmpty, isTrue);

      bloc.close();
    });
  });
}
