import 'dart:async';

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

class MockHistoryRepo extends HttpChatRepository {
  final List<ChatMessage> historyMessages;

  MockHistoryRepo({this.historyMessages = const []});

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  }) async {
    return CursorPaginationResponse(
      current: sinceId?.toString() ?? beforeId,
      data: historyMessages,
      fromJsonFactory: ChatMessage.fromJson,
      toJsonFactory: (m) => m.toJson(),
      hasMore: false,
    );
  }
}

class ControlledHistoryRepo extends HttpChatRepository {
  final Completer<CursorPaginationResponse<ChatMessage>> completer;
  final List<ChatMessage> deltaMessages;

  ControlledHistoryRepo({
    required this.completer,
    this.deltaMessages = const [],
  });

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  }) async {
    if (sinceId != null) {
      return CursorPaginationResponse(
        current: sinceId.toString(),
        data: deltaMessages,
        fromJsonFactory: ChatMessage.fromJson,
        toJsonFactory: (m) => m.toJson(),
        hasMore: false,
      );
    }
    return completer.future;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Lifecycle Reliability Fixes Tests', () {
    test('Test 1 — Global echo while no ChatInboxScreen exists removes matching outbox item', () async {
      const clientMsgId = 'uuid-global-echo-1';
      final outbox = InMemoryOutboxStorage();
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: clientMsgId,
          conversationId: 'conv-1',
          content: 'Hello global',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      final coordinator = ChatSyncCoordinator(
        outboxStorage: outbox,
        currentUserIdProvider: () => 'me-1',
      );

      // Verify no active screen is mounted
      expect(coordinator.activeInboxBloc, isNull);

      // Incoming new_message echo sent by current user
      await coordinator.handleGlobalNewMessage({
        'id': '101',
        'client_message_id': clientMsgId,
        'sender_id': 'me-1',
        'conversation_id': 'conv-1',
        'content': 'Hello global',
      });

      // Outbox item must be removed
      final pending = await outbox.getAllMessages();
      expect(pending, isEmpty);
    });

    test('Test 2 — Incoming message from another user does not remove outbox item', () async {
      const clientMsgId = 'my-uuid-1';
      final outbox = InMemoryOutboxStorage();
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: clientMsgId,
          conversationId: 'conv-1',
          content: 'My pending message',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      final coordinator = ChatSyncCoordinator(
        outboxStorage: outbox,
        currentUserIdProvider: () => 'me-1',
      );

      // Incoming message from Bob
      await coordinator.handleGlobalNewMessage({
        'id': '102',
        'client_message_id': 'bob-uuid-2',
        'sender_id': 'bob-user',
        'conversation_id': 'conv-1',
        'content': 'Hello from Bob',
      });

      // My pending message must remain in outbox
      final pending = await outbox.getAllMessages();
      expect(pending.length, equals(1));
      expect(pending.first.clientMessageId, equals(clientMsgId));
    });

    test('Test 3 — Initial REST load reconciles outbox items without touching unrelated items', () async {
      const clientMsgIdPersisted = 'uuid-rest-persisted';
      const clientMsgIdUnresolved = 'uuid-rest-unresolved';
      final outbox = InMemoryOutboxStorage();

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: clientMsgIdPersisted,
          conversationId: 'conv-1',
          content: 'Persisted on server',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: clientMsgIdUnresolved,
          conversationId: 'conv-1',
          content: 'Still pending',
          createdAt: DateTime.utc(2026, 10, 6, 12, 1),
        ),
      );

      final serverMsg = ChatMessage(
        id: '301',
        clientMessageId: clientMsgIdPersisted,
        senderId: 'me-1',
        receiverId: 'conv-1',
        message: 'Persisted on server',
        sentAt: DateTime.utc(2026, 10, 6, 12, 0),
        isMine: true,
      );

      final repo = MockHistoryRepo(historyMessages: [serverMsg]);
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: repo,
        outboxStorage: outbox,
      );

      // Trigger initial load
      bloc.execute(pageFromStart: true);
      await pumpEventQueue();

      // The server-confirmed message must be removed; the unresolved one must remain
      final pendingAfter = await outbox.getAllMessages();
      expect(pendingAfter.length, equals(1));
      expect(pendingAfter.first.clientMessageId, equals(clientMsgIdUnresolved));

      bloc.close();
    });

    test('Test 4 — Reconnect during initial load defers and resumes recovery when load completes', () async {
      const clientMsgId = 'uuid-race-1';
      final outbox = InMemoryOutboxStorage();
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: clientMsgId,
          conversationId: 'conv-1',
          content: 'Retry me after load',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      final repoCompleter = Completer<CursorPaginationResponse<ChatMessage>>();
      final delayedRepo = ControlledHistoryRepo(completer: repoCompleter);

      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: delayedRepo,
        outboxStorage: outbox,
      );

      final sentMessages = <String>[];
      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) {
          sentMessages.add(clientMessageId);
        },
      );

      final coordinator = ChatSyncCoordinator(
        outboxProcessor: processor,
        outboxStorage: outbox,
        isConnectedOverride: () => true,
      );

      coordinator.registerActiveBloc(bloc);

      // 1. Start initial load (in flight)
      bloc.execute(pageFromStart: true);
      expect(bloc.isInitialLoading, isTrue);

      // 2. Socket reconnects while initial load is in flight
      final initialReconnectResult = await coordinator.handleReconnect(inboxBloc: bloc);
      // Recovery must be deferred, not lost
      expect(initialReconnectResult, isFalse);
      expect(coordinator.isRecoveryPending, isTrue);
      expect(sentMessages, isEmpty);

      // 3. Initial load completes
      repoCompleter.complete(
        CursorPaginationResponse(
          data: [
            ChatMessage(
              id: '200',
              senderId: 'other-1',
              receiverId: 'conv-1',
              message: 'Existing history',
              sentAt: DateTime.utc(2026, 10, 6, 11, 0),
            ),
          ],
          fromJsonFactory: ChatMessage.fromJson,
          toJsonFactory: (m) => m.toJson(),
          hasMore: false,
        ),
      );

      await pumpEventQueue();

      // Recovery must have resumed and processed the pending outbox item
      expect(coordinator.isRecoveryPending, isFalse);
      expect(sentMessages, equals([clientMsgId]));

      bloc.close();
    });

    test('Test 5 — No duplicate recovery runs when reconnect and initial load overlap', () async {
      final outbox = InMemoryOutboxStorage();
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'uuid-no-dup',
          conversationId: 'conv-1',
          content: 'Unique message',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );

      int processRunCount = 0;
      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) {
          processRunCount++;
        },
      );

      final repoCompleter = Completer<CursorPaginationResponse<ChatMessage>>();
      final delayedRepo = ControlledHistoryRepo(completer: repoCompleter);
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: delayedRepo,
        outboxStorage: outbox,
      );

      final coordinator = ChatSyncCoordinator(
        outboxProcessor: processor,
        outboxStorage: outbox,
        isConnectedOverride: () => true,
      );
      coordinator.registerActiveBloc(bloc);

      bloc.execute(pageFromStart: true);
      expect(bloc.isInitialLoading, isTrue);

      // Multiple reconnect recovery calls while initial load is in flight
      await coordinator.handleReconnect();
      await coordinator.handleReconnect();

      // Complete initial load
      repoCompleter.complete(
        CursorPaginationResponse(
          data: [
            ChatMessage(
              id: '100',
              senderId: 'other',
              receiverId: 'conv-1',
              message: 'Loaded',
              sentAt: DateTime.utc(2026, 10, 6, 10, 0),
            ),
          ],
          fromJsonFactory: ChatMessage.fromJson,
          toJsonFactory: (m) => m.toJson(),
          hasMore: false,
        ),
      );

      await pumpEventQueue();

      // Outbox process should run exactly once
      expect(processRunCount, equals(1));

      bloc.close();
    });

    test('Test 6 — Multiple conversations retried with their respective conversation IDs', () async {
      final outbox = InMemoryOutboxStorage();
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-a',
          conversationId: 'conv-A',
          content: 'Content A',
          createdAt: DateTime.utc(2026, 10, 6, 12, 0),
        ),
      );
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-b',
          conversationId: 'conv-B',
          content: 'Content B',
          createdAt: DateTime.utc(2026, 10, 6, 12, 1),
        ),
      );

      final sent = <Map<String, String>>[];
      final processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required conversationId,
          required content,
          required clientMessageId,
          messageType = 'text',
        }) {
          sent.add({
            'conv': conversationId,
            'clientMsgId': clientMessageId,
            'content': content,
          });
        },
      );

      final coordinator = ChatSyncCoordinator(
        outboxProcessor: processor,
        outboxStorage: outbox,
      );

      // Reconnect with no active screen
      await coordinator.handleReconnect();

      expect(sent.length, equals(2));
      expect(sent[0]['conv'], equals('conv-A'));
      expect(sent[0]['clientMsgId'], equals('msg-a'));
      expect(sent[1]['conv'], equals('conv-B'));
      expect(sent[1]['clientMsgId'], equals('msg-b'));
    });

    test('Fix 7 Invariants — Cases A, B, C, D produce exactly one authoritative message', () async {
      final outbox = InMemoryOutboxStorage();
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        outboxStorage: outbox,
      );

      // Baseline: optimistic message X
      const clientMsgId = 'uuid-reconcile-all';
      await bloc.sendOutgoingMessage(
        content: 'Optimistic message',
        clientMessageId: clientMsgId,
        currentUserId: 'me-1',
      );

      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.clientMessageId, equals(clientMsgId));
      expect(bloc.cursorPageHolder.items.first.id.isEmpty, isTrue);

      // Case A: live echo arrives with server integer id 501
      await bloc.reconcileServerMessage(
        ChatMessage(
          id: '501',
          clientMessageId: clientMsgId,
          senderId: 'me-1',
          receiverId: 'conv-1',
          message: 'Optimistic message',
          sentAt: DateTime.utc(2026, 10, 6, 12, 0),
          isMine: true,
        ),
      );

      // Exactly 1 message in list with authoritative ID 501
      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.id, equals('501'));
      expect(bloc.cursorPageHolder.items.first.clientMessageId, equals(clientMsgId));

      // Case D: later delta sync arrives with same id 501 and clientMessageId
      await bloc.reconcileServerMessage(
        ChatMessage(
          id: '501',
          clientMessageId: clientMsgId,
          senderId: 'me-1',
          receiverId: 'conv-1',
          message: 'Optimistic message',
          sentAt: DateTime.utc(2026, 10, 6, 12, 0),
          isMine: true,
          isDelivered: true,
        ),
      );

      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.id, equals('501'));
      expect(bloc.cursorPageHolder.items.first.isDelivered, isTrue);

      bloc.close();
    });
  });
}
