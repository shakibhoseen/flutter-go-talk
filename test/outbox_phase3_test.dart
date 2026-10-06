import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_outbox_processor.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_sync_coordinator.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/local_outbox_storage.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/pending_outbox_message.dart';
import 'package:whatsapp_flutter_go/feature/home/data/http_chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';

class MockDeltaRepoForPhase3 extends HttpChatRepository {
  final List<ChatMessage> deltaMessages;
  final bool shouldFail;

  MockDeltaRepoForPhase3({
    this.deltaMessages = const [],
    this.shouldFail = false,
  });

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  }) async {
    if (shouldFail) {
      throw Exception('Simulated network error during delta sync');
    }
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

  group('Phase 3: Outbox Recovery & Reconnect Tests', () {
    test('Test A — reconnect recovers server-persisted message (delta sync finds X, outbox removed, X NOT retried)', () async {
      const clientMsgId = 'uuid-test-a-persisted';
      final outbox = InMemoryOutboxStorage();

      // Persist pending message X in outbox
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: clientMsgId,
          conversationId: 'conv-10',
          content: 'Persisted on server',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      // Server already persisted X as sequence id 501
      final serverDeltaMsg = ChatMessage(
        id: '501',
        clientMessageId: clientMsgId,
        senderId: 'me-1',
        receiverId: 'conv-10',
        message: 'Persisted on server',
        sentAt: DateTime.utc(2026, 10, 6, 12, 0),
        isMine: true,
      );

      final repo = MockDeltaRepoForPhase3(deltaMessages: [serverDeltaMsg]);
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-10',
        repository: repo,
        outboxStorage: outbox,
      );

      // Baseline acknowledged message so latestMessageId == 480
      bloc.upsertLocalItem(
        ChatMessage(
          id: '480',
          receiverId: 'conv-10',
          senderId: 'user-2',
          message: 'Older message',
          sentAt: DateTime.utc(2026, 10, 6, 11, 0),
        ),
        emitState: false,
      );

      // Local optimistic message
      bloc.upsertLocalItem(
        ChatMessage(
          id: '',
          clientMessageId: clientMsgId,
          senderId: 'me-1',
          receiverId: 'conv-10',
          message: 'Persisted on server',
          sentAt: DateTime.utc(2026, 10, 6, 12, 0),
          isMine: true,
        ),
        emitState: false,
      );

      final sentMessages = <Map<String, dynamic>>[];
      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) {
          sentMessages.add({
            'conversationId': conversationId,
            'content': content,
            'clientMessageId': clientMessageId,
          });
        },
      );

      final coordinator = ChatSyncCoordinator(outboxProcessor: processor);

      // Reconnect flow
      final success = await coordinator.handleReconnect(inboxBloc: bloc);
      expect(success, isTrue);

      // 1. Local message reconciled
      final item = bloc.cursorPageHolder.items.firstWhere(
        (m) => m.clientMessageId == clientMsgId,
      );
      expect(item.id, equals('501'));

      // 2. X removed from outbox
      final pendingAfter = await outbox.getAllMessages();
      expect(pendingAfter.isEmpty, isTrue);

      // 3. X was NOT retried
      expect(sentMessages.isEmpty, isTrue,
          reason: 'Message X was reconciled in delta sync and must NOT be retried');

      bloc.close();
    });

    test('Test B — reconnect retries unresolved message (delta sync does NOT find X, retries same clientMessageId)', () async {
      const clientMsgId = 'uuid-test-b-unresolved';
      final outbox = InMemoryOutboxStorage();

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: clientMsgId,
          conversationId: 'conv-10',
          content: 'Unresolved text',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      // Server delta sync has NO messages (X was dropped before server persisted it)
      final repo = MockDeltaRepoForPhase3(deltaMessages: []);
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-10',
        repository: repo,
        outboxStorage: outbox,
      );

      bloc.upsertLocalItem(
        ChatMessage(
          id: '480',
          receiverId: 'conv-10',
          senderId: 'user-2',
          message: 'Older message',
          sentAt: DateTime.utc(2026, 10, 6, 11, 0),
        ),
        emitState: false,
      );

      final sentMessages = <Map<String, dynamic>>[];
      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) {
          sentMessages.add({
            'conversationId': conversationId,
            'content': content,
            'clientMessageId': clientMessageId,
          });
        },
      );

      final coordinator = ChatSyncCoordinator(outboxProcessor: processor);

      final success = await coordinator.handleReconnect(inboxBloc: bloc);
      expect(success, isTrue);

      // 1. Sent message retry contains exact same clientMessageId
      expect(sentMessages.length, equals(1));
      expect(sentMessages.first['clientMessageId'], equals(clientMsgId));
      expect(sentMessages.first['conversationId'], equals('conv-10'));
      expect(sentMessages.first['content'], equals('Unresolved text'));

      // 2. Outbox X STILL exists (not removed on send)
      final pendingAfter = await outbox.getAllMessages();
      expect(pendingAfter.length, equals(1));
      expect(pendingAfter.first.clientMessageId, equals(clientMsgId));

      bloc.close();
    });

    test('Test C — retry never generates a new client ID (uses original abc-123)', () async {
      const originalClientId = 'abc-123-fixed-id';
      final outbox = InMemoryOutboxStorage();

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: originalClientId,
          conversationId: 'conv-c',
          content: 'Fixed client ID test',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      final sentClientIds = <String>[];
      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) {
          sentClientIds.add(clientMessageId);
        },
      );

      await processor.processPending();

      expect(sentClientIds, equals([originalClientId]),
          reason: 'Retried message must use the exact original clientMessageId without generating a new UUID');
    });

    test('Test D — disconnected during processing (X sends, socket drops, both X and Y remain in outbox)', () async {
      final outbox = InMemoryOutboxStorage();

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-X',
          conversationId: 'conv-d',
          content: 'Message X',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-Y',
          conversationId: 'conv-d',
          content: 'Message Y',
          createdAt: DateTime.utc(2026, 10, 6, 12, 1),
        ),
      );

      var isConnected = true;
      final sentMessages = <String>[];

      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => isConnected,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) {
          sentMessages.add(clientMessageId);
          // Simulate connection dropping right after message X
          isConnected = false;
        },
      );

      await processor.processPending();

      // Only X was sent before disconnection was detected
      expect(sentMessages, equals(['msg-X']));

      // Both X and Y must remain in outbox!
      final remaining = await outbox.getAllMessages();
      expect(remaining.length, equals(2));
      expect(remaining.any((m) => m.clientMessageId == 'msg-X'), isTrue);
      expect(remaining.any((m) => m.clientMessageId == 'msg-Y'), isTrue);
    });

    test('Test E — concurrent process protection (calling processPending concurrently only runs one loop)', () async {
      final outbox = InMemoryOutboxStorage();

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-concurrent',
          conversationId: 'conv-e',
          content: 'Concurrent test',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      var sendCount = 0;
      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) async {
          sendCount++;
          // Simulate slight asynchronous processing latency
          await Future.delayed(const Duration(milliseconds: 30));
        },
      );

      // Trigger 3 concurrent calls
      await Future.wait([
        processor.processPending(),
        processor.processPending(),
        processor.processPending(),
      ]);

      expect(sendCount, equals(1),
          reason: 'Concurrency guard must prevent duplicate processing runs');
    });

    test('Test F — app restart persistence (save X, recreate storage, X still exists)', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage1 = SharedPreferencesOutboxStorage(prefs);

      await storage1.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-restart-X',
          conversationId: 'conv-f',
          content: 'Survives restart',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      // Simulate app restart by discarding storage1 and creating storage2 from disk prefs
      final storage2 = SharedPreferencesOutboxStorage(prefs);
      final restored = await storage2.getAllMessages();

      expect(restored.length, equals(1));
      expect(restored.first.clientMessageId, equals('msg-restart-X'));
      expect(restored.first.content, equals('Survives restart'));
    });

    test('Test G — multiple conversations (A -> X, B -> Y sent with respective conversation IDs)', () async {
      final outbox = InMemoryOutboxStorage();

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-X',
          conversationId: 'conv-A',
          content: 'For Conversation A',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-Y',
          conversationId: 'conv-B',
          content: 'For Conversation B',
          createdAt: DateTime.utc(2026, 10, 6, 12, 1),
        ),
      );

      final sentMap = <String, String>{};
      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) {
          sentMap[clientMessageId] = conversationId;
        },
      );

      await processor.processPending();

      expect(sentMap.length, equals(2));
      expect(sentMap['msg-X'], equals('conv-A'));
      expect(sentMap['msg-Y'], equals('conv-B'));
    });

    test('Test H — incoming message does not affect outbox', () async {
      final outbox = InMemoryOutboxStorage();
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-h',
        outboxStorage: outbox,
      );

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'our-msg-X',
          conversationId: 'conv-h',
          content: 'Our text',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      // Incoming message from user 2
      final incomingBob = ChatMessage(
        id: '999',
        clientMessageId: 'bob-msg-Y',
        senderId: 'user-2',
        receiverId: 'conv-h',
        message: 'Hello from Bob',
        sentAt: DateTime.utc(2026, 10, 6, 12, 1),
        isMine: false,
      );

      await bloc.handleNewMessage(message: incomingBob);

      final pending = await outbox.getAllMessages();
      expect(pending.length, equals(1));
      expect(pending.first.clientMessageId, equals('our-msg-X'));

      bloc.close();
    });

    test('Test I — echo arrives during retry (X removed from outbox before send step, so skipped and not re-sent)', () async {
      final outbox = InMemoryOutboxStorage();

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-race-X',
          conversationId: 'conv-i',
          content: 'Racing echo message',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      // Simulate live echo arriving and removing X right after snapshot was taken
      await outbox.remove('msg-race-X');

      final sentList = <String>[];
      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) {
          sentList.add(clientMessageId);
        },
      );

      await processor.processPending();

      expect(sentList.isEmpty, isTrue,
          reason: 'Processor must re-check outbox existence before sending and skip already-reconciled messages');
    });

    test('Test J — delta sync failure (syncMissedMessages returns false, outbox X remains, processPending is NOT called)', () async {
      const clientMsgId = 'msg-fail-test';
      final outbox = InMemoryOutboxStorage();

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: clientMsgId,
          conversationId: 'conv-j',
          content: 'Failing sync message',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      final failingRepo = MockDeltaRepoForPhase3(shouldFail: true);
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-j',
        repository: failingRepo,
        outboxStorage: outbox,
      );

      bloc.upsertLocalItem(
        ChatMessage(
          id: '480',
          receiverId: 'conv-j',
          senderId: 'user-2',
          message: 'Baseline message',
          sentAt: DateTime.utc(2026, 10, 6, 11, 0),
        ),
        emitState: false,
      );

      var processPendingCalled = false;
      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) {
          processPendingCalled = true;
        },
      );

      final coordinator = ChatSyncCoordinator(outboxProcessor: processor);

      final success = await coordinator.handleReconnect(inboxBloc: bloc);

      // Delta sync failed
      expect(success, isFalse);

      // processPending must NOT have been called
      expect(processPendingCalled, isFalse);

      // Outbox item X must remain persisted
      final pendingAfter = await outbox.getAllMessages();
      expect(pendingAfter.length, equals(1));
      expect(pendingAfter.first.clientMessageId, equals(clientMsgId));

      bloc.close();
    });
  });
}
