import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_flutter_go/core/db/local_cache/chat_message_cache.dart';
import 'package:whatsapp_flutter_go/core/db/local_cache/hive_initializer.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_outbox_processor.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/local_outbox_storage.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/pending_outbox_message.dart';
import 'package:whatsapp_flutter_go/feature/home/data/http_chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';

class MockControlledHistoryRepo extends HttpChatRepository {
  final Future<CursorPaginationResponse<ChatMessage>> Function(
    String conversationId, {
    int limit,
    String? beforeId,
    int? sinceId,
  })? onGetMessages;

  const MockControlledHistoryRepo({this.onGetMessages});

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  }) async {
    if (onGetMessages != null) {
      return onGetMessages!(
        conversationId,
        limit: limit,
        beforeId: beforeId,
        sinceId: sinceId,
      );
    }
    return CursorPaginationResponse(
      data: [],
      hasMore: false,
      fromJsonFactory: ChatMessage.fromJson,
      toJsonFactory: (m) => m.toJson(),
    );
  }
}

class PausableOutboxStorage extends InMemoryOutboxStorage {
  Completer<void>? pauseGetMessagesCompleter;
  Completer<void>? onGetMessagesStartedCompleter;

  @override
  Future<List<PendingOutboxMessage>> getMessagesForConversation(
    String conversationId, {
    String? targetUserScope,
  }) async {
    if (pauseGetMessagesCompleter != null && !pauseGetMessagesCompleter!.isCompleted) {
      if (onGetMessagesStartedCompleter != null && !onGetMessagesStartedCompleter!.isCompleted) {
        onGetMessagesStartedCompleter!.complete();
      }
      await pauseGetMessagesCompleter!.future;
    }
    return super.getMessagesForConversation(conversationId, targetUserScope: targetUserScope);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('msg_cache_test_');
    SharedPreferences.setMockInitialValues({});
    HiveInitializer.resetForTesting();
    ChatMessageCache().resetForTesting();
    ChatMessageCache.userScopeResolver =
        () => AuthSession.tokens?.user?.id?.toString() ?? 'guest';
    await HiveInitializer.ensureInitialized(tempDir.path);
  });

  tearDown(() async {
    await AuthSession.clear();
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    HiveInitializer.resetForTesting();
    ChatMessageCache().resetForTesting();
  });

  ChatMessage createMessage({
    required String id,
    String? clientMessageId,
    required String content,
    String senderId = '101',
    String conversationId = 'conv-1',
    DateTime? sentAt,
    bool isMine = true,
    bool isDelivered = true,
    bool isSeen = false,
    String senderName = 'Alice',
    String senderAvatar = 'avatar.png',
    List<ReadReceiptUser> readBy = const [],
    int readCount = 0,
  }) {
    final now = sentAt ?? DateTime.now();
    return ChatMessage(
      id: id,
      clientMessageId: clientMessageId,
      senderId: senderId,
      receiverId: conversationId,
      message: content,
      sentAt: now,
      isMine: isMine,
      isDelivered: isDelivered,
      isSeen: isSeen,
      senderName: senderName,
      senderAvatar: senderAvatar,
      readBy: readBy,
      readCount: readCount,
      timeStamp: TimeStamp.fromDatePublish(now.millisecondsSinceEpoch),
    );
  }

  group('Phase 2A: Persistent Cache-First Message History & Outbox Hydration', () {
    test('1. Confirmed messages survive Hive close/reopen and restore offline with full fidelity', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-100';

      final m1 = createMessage(
        id: '1',
        clientMessageId: 'c-1',
        content: 'First confirmed message',
        senderName: 'Alice',
        senderAvatar: 'alice.png',
        readCount: 2,
        readBy: const [
          ReadReceiptUser(userId: 102, name: 'Bob', avatarUrl: 'bob.png'),
          ReadReceiptUser(userId: 103, name: 'Charlie', avatarUrl: 'charlie.png'),
        ],
      );
      final m2 = createMessage(
        id: '2',
        clientMessageId: 'c-2',
        content: 'Second confirmed message',
        senderName: 'Alice',
        senderAvatar: 'alice.png',
      );

      // Simulate user 101 logged in
      ChatMessageCache.userScopeResolver = () => '101';

      // Save to cache
      await cache.saveMessages(
        conversationId: conversationId,
        messages: [m2, m1],
        targetUserScope: '101',
      );

      // Simulate app kill: close Hive
      await Hive.close();
      cache.resetForTesting();
      HiveInitializer.resetForTesting();

      // Simulate cold restart: reinitialize Hive with same disk directory
      await HiveInitializer.ensureInitialized(tempDir.path);
      final reopenedCache = ChatMessageCache();

      // Read back
      final result = await reopenedCache.getMessages(
        conversationId: conversationId,
        targetUserScope: '101',
      );

      expect(result, isNotNull);
      expect(result!.messages.length, equals(2));

      final restoredM2 = result.messages[0];
      final restoredM1 = result.messages[1];

      expect(restoredM2.id, equals('2'));
      expect(restoredM2.clientMessageId, equals('c-2'));
      expect(restoredM2.message, equals('Second confirmed message'));
      expect(restoredM2.senderName, equals('Alice'));

      expect(restoredM1.id, equals('1'));
      expect(restoredM1.clientMessageId, equals('c-1'));
      expect(restoredM1.readCount, equals(2));
      expect(restoredM1.readBy.length, equals(2));
      expect(restoredM1.readBy[0].name, equals('Bob'));
      expect(restoredM1.readBy[1].name, equals('Charlie'));
    });

    test('2. Opening chat offline renders cached confirmed messages promptly before network', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-200';

      final m1 = createMessage(id: '1', content: 'Cached msg 1');
      final m2 = createMessage(id: '2', content: 'Cached msg 2');

      await cache.saveMessages(
        conversationId: conversationId,
        messages: [m2, m1],
        targetUserScope: 'guest',
      );

      final networkCompleter = Completer<CursorPaginationResponse<ChatMessage>>();
      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) =>
            networkCompleter.future,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        messageCache: cache,
      );

      bloc.execute();
      expect(bloc.isInitialLoading, isTrue);

      // Await initial hydration
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // Cached view must be rendered immediately while network request is still pending
      expect(bloc.cursorPageHolder.items.length, equals(2));
      expect(bloc.cursorPageHolder.items[0].id, equals('2'));
      expect(bloc.cursorPageHolder.items[1].id, equals('1'));
      expect(networkCompleter.isCompleted, isFalse);

      bloc.close();
    });

    test('3. Pending outbox messages reappear on reopening and deduplicate with server-confirmed history', () async {
      final cache = ChatMessageCache();
      final outbox = InMemoryOutboxStorage();
      const conversationId = 'conv-300';
      const clientMsgId = 'uuid-draft-1';

      // 1. Seed cache with older confirmed message
      final mConfirmed = createMessage(id: '10', content: 'Old confirmed');
      await cache.saveMessages(
        conversationId: conversationId,
        messages: [mConfirmed],
        targetUserScope: 'guest',
      );

      // 2. Outbox has pending message from offline send
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: clientMsgId,
          conversationId: conversationId,
          content: 'Pending offline message',
          createdAt: DateTime.now(),
        ),
      );

      final networkCompleter = Completer<CursorPaginationResponse<ChatMessage>>();
      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) =>
            networkCompleter.future,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        outboxStorage: outbox,
        messageCache: cache,
      );

      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // Both pending outbox item and cached confirmed item appear
      expect(bloc.cursorPageHolder.items.length, equals(2));
      expect(bloc.cursorPageHolder.items[0].clientMessageId, equals(clientMsgId));
      expect(bloc.cursorPageHolder.items[0].id, isEmpty); // Pending
      expect(bloc.cursorPageHolder.items[1].id, equals('10'));

      // 3. Server responds confirming the pending message
      final serverConfirmed = ChatMessage(
        id: '11',
        clientMessageId: clientMsgId,
        senderId: 'guest',
        receiverId: conversationId,
        message: 'Pending offline message',
        sentAt: DateTime.now(),
        isMine: true,
      );

      networkCompleter.complete(
        CursorPaginationResponse(
          data: [serverConfirmed, mConfirmed],
          fromJsonFactory: ChatMessage.fromJson,
          toJsonFactory: (m) => m.toJson(),
          hasMore: false,
        ),
      );
      await pumpEventQueue();

      // Reconciled without duplication: exactly 2 messages in list
      expect(bloc.cursorPageHolder.items.length, equals(2));
      expect(bloc.cursorPageHolder.items[0].id, equals('11'));
      expect(bloc.cursorPageHolder.items[0].clientMessageId, equals(clientMsgId));

      // Outbox item must be removed from storage
      final remainingOutbox = await outbox.getAllMessages();
      expect(remainingOutbox, isEmpty);

      bloc.close();
    });

    test('4. Unresolved pending outbox message is NOT erased when server history arrives', () async {
      final cache = ChatMessageCache();
      final outbox = InMemoryOutboxStorage();
      const conversationId = 'conv-400';
      const clientMsgIdUnresolved = 'uuid-unresolved-1';

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: clientMsgIdUnresolved,
          conversationId: conversationId,
          content: 'Unresolved message',
          createdAt: DateTime.now(),
        ),
      );

      final serverMsg1 = createMessage(id: '101', content: 'Server message 1');
      final serverMsg2 = createMessage(id: '100', content: 'Server message 2');

      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) async {
          return CursorPaginationResponse(
            data: [serverMsg1, serverMsg2],
            fromJsonFactory: ChatMessage.fromJson,
            toJsonFactory: (m) => m.toJson(),
            hasMore: false,
          );
        },
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        outboxStorage: outbox,
        messageCache: cache,
      );

      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // The unresolved pending message MUST remain at index 0, followed by server messages
      expect(bloc.cursorPageHolder.items.length, equals(3));
      expect(bloc.cursorPageHolder.items[0].clientMessageId, equals(clientMsgIdUnresolved));
      expect(bloc.cursorPageHolder.items[0].id, isEmpty);
      expect(bloc.cursorPageHolder.items[1].id, equals('101'));
      expect(bloc.cursorPageHolder.items[2].id, equals('100'));

      // Pending message must still be in outbox storage
      final pending = await outbox.getAllMessages();
      expect(pending.length, equals(1));
      expect(pending.first.clientMessageId, equals(clientMsgIdUnresolved));

      bloc.close();
    });

    test('5. Network failure retains and displays cached messages and pending outgoing messages', () async {
      final cache = ChatMessageCache();
      final outbox = InMemoryOutboxStorage();
      const conversationId = 'conv-500';

      final m1 = createMessage(id: '50', content: 'Cached item');
      await cache.saveMessages(
        conversationId: conversationId,
        messages: [m1],
        targetUserScope: 'guest',
      );

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'p-500',
          conversationId: conversationId,
          content: 'Pending item',
          createdAt: DateTime.now(),
        ),
      );

      // Network throws offline connection error
      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) async {
          throw DioException(
            requestOptions: RequestOptions(path: '/conversations/$convId/messages'),
            type: DioExceptionType.connectionError,
            error: 'No internet connection',
          );
        },
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        outboxStorage: outbox,
        messageCache: cache,
      );

      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // Items must be retained and visible despite network failure
      expect(bloc.cursorPageHolder.items.length, equals(2));
      expect(bloc.cursorPageHolder.items[0].clientMessageId, equals('p-500'));
      expect(bloc.cursorPageHolder.items[1].id, equals('50'));

      // Initial loading flag cleared
      expect(bloc.isInitialLoading, isFalse);
      expect(bloc.hasInitialLoaded, isTrue);

      bloc.close();
    });

    test('6. User A history cannot be accessed or overwritten by User B (User Scope Isolation)', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-shared';

      // User A logged in
      ChatMessageCache.userScopeResolver = () => '101';
      final msgA = createMessage(
        id: '1',
        content: "Secret of User A",
        senderId: '101',
      );
      await cache.saveMessages(
        conversationId: conversationId,
        messages: [msgA],
        targetUserScope: '101',
      );

      // User B logs in
      ChatMessageCache.userScopeResolver = () => '102';
      final resultB = await cache.getMessages(
        conversationId: conversationId,
        targetUserScope: '102',
      );

      expect(resultB, isNull);

      // User B caches their own messages
      final msgB = createMessage(
        id: '2',
        content: "User B message",
        senderId: '102',
      );
      await cache.saveMessages(
        conversationId: conversationId,
        messages: [msgB],
        targetUserScope: '102',
      );

      // User A logs back in
      ChatMessageCache.userScopeResolver = () => '101';
      final resultA = await cache.getMessages(
        conversationId: conversationId,
        targetUserScope: '101',
      );
      expect(resultA, isNotNull);
      expect(resultA!.messages.first.message, equals("Secret of User A"));

      // User B logs back in
      ChatMessageCache.userScopeResolver = () => '102';
      final recheckB = await cache.getMessages(
        conversationId: conversationId,
        targetUserScope: '102',
      );
      expect(recheckB, isNotNull);
      expect(recheckB!.messages.first.message, equals("User B message"));
    });

    test('7. Delayed old-session write cannot populate a new session cache (Session Epoch Protection)', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-700';

      // User A starts with epoch 0
      final capturedEpoch = cache.sessionEpoch;
      final capturedScope = '101';

      // User A logs out -> clearAll increments epoch
      await cache.clearAll();
      expect(cache.sessionEpoch, greaterThan(capturedEpoch));

      // User B logs in
      ChatMessageCache.userScopeResolver = () => '102';

      // Delayed write from User A's session completes now
      final staleMessage = createMessage(id: '999', content: 'Stale delayed msg');
      await cache.saveMessages(
        conversationId: conversationId,
        messages: [staleMessage],
        targetUserScope: capturedScope,
        sessionEpoch: capturedEpoch,
      );

      // Stale write was aborted
      final readA = await cache.getMessages(
        conversationId: conversationId,
        targetUserScope: '101',
      );
      expect(readA, isNull);

      final readB = await cache.getMessages(
        conversationId: conversationId,
        targetUserScope: '102',
      );
      expect(readB, isNull);
    });

    test('8. Coordinated logout clear prevents User B cache wipe', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-800';

      final clearHold = Completer<void>();
      ChatMessageCache.clearHoldCompleter = clearHold;

      // User A triggers clearAll
      final clearFuture = cache.clearAll();

      // User B signs in while clear is still in-flight
      ChatMessageCache.userScopeResolver = () => '102';

      // User B writes cache (coordinated write awaits pendingClearFuture)
      final userBWriteFuture = cache.saveMessages(
        conversationId: conversationId,
        messages: [createMessage(id: '201', content: "User B fresh data")],
        targetUserScope: '102',
      );

      // Release clear hold
      clearHold.complete();
      await clearFuture;
      await userBWriteFuture;

      // User B's cache must be preserved and not wiped by User A's logout clear
      final resultB = await cache.getMessages(
        conversationId: conversationId,
        targetUserScope: '102',
      );
      expect(resultB, isNotNull);
      expect(resultB!.messages.first.message, equals("User B fresh data"));
    });

    test('9. Live WebSocket echo / new message updates cache', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-900';

      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        messageCache: cache,
      );

      final incoming = createMessage(
        id: '501',
        content: 'Incoming live message',
        senderId: '202',
      );

      await bloc.handleNewMessage(message: incoming);
      await pumpEventQueue();

      final cached = await cache.getMessages(conversationId: conversationId);
      expect(cached, isNotNull);
      expect(cached!.messages.length, equals(1));
      expect(cached.messages.first.id, equals('501'));
      expect(cached.messages.first.message, equals('Incoming live message'));

      bloc.close();
    });

    test('10. Cache-first ordering invariant: newest pending (index 0) down to oldest confirmed', () async {
      final cache = ChatMessageCache();
      final outbox = InMemoryOutboxStorage();
      const conversationId = 'conv-1000';

      final baseTime = DateTime.utc(2026, 10, 10, 10, 0);

      // Two confirmed messages (older)
      final mOld1 = createMessage(
        id: '1',
        content: 'Confirmed 1',
        sentAt: baseTime,
      );
      final mOld2 = createMessage(
        id: '2',
        content: 'Confirmed 2',
        sentAt: baseTime.add(const Duration(minutes: 1)),
      );

      await cache.saveMessages(
        conversationId: conversationId,
        messages: [mOld2, mOld1], // Descending: 2, 1
        targetUserScope: 'guest',
      );

      // Two pending messages sent while offline
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'pending-1',
          conversationId: conversationId,
          content: 'Pending 1 (earlier)',
          createdAt: baseTime.add(const Duration(minutes: 5)),
        ),
      );
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'pending-2',
          conversationId: conversationId,
          content: 'Pending 2 (later)',
          createdAt: baseTime.add(const Duration(minutes: 6)),
        ),
      );

      final networkCompleter = Completer<CursorPaginationResponse<ChatMessage>>();
      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) =>
            networkCompleter.future,
      );
      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        outboxStorage: outbox,
        messageCache: cache,
      );

      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      final items = bloc.cursorPageHolder.items;
      expect(items.length, equals(4));

      // Strict reverse list order:
      // Index 0: newest pending ('pending-2')
      // Index 1: earlier pending ('pending-1')
      // Index 2: newest confirmed ('2')
      // Index 3: oldest confirmed ('1')
      expect(items[0].clientMessageId, equals('pending-2'));
      expect(items[1].clientMessageId, equals('pending-1'));
      expect(items[2].id, equals('2'));
      expect(items[3].id, equals('1'));

      bloc.close();
    });
  });

  group('Phase 2A Fixes: Regression Tests for Outbox Isolation & Concurrent Reconciliation', () {
    test('11. Fix 1: User A offline pending message does not appear in User B UI and is not sent using B credentials', () async {
      final cache = ChatMessageCache();
      final outbox = InMemoryOutboxStorage();
      const conversationId = 'conv-leak-1';

      // User A (101) saves a pending outbox message
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-from-user-a',
          conversationId: conversationId,
          content: 'Secret from A',
          createdAt: DateTime.now(),
          senderId: '101',
        ),
      );

      // User A logs out and User B (202) logs in
      ChatMessageCache.userScopeResolver = () => '202';

      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) async =>
            CursorPaginationResponse(
              data: [],
              hasMore: false,
              fromJsonFactory: ChatMessage.fromJson,
              toJsonFactory: (m) => m.toJson(),
            ),
      );

      final blocB = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        outboxStorage: outbox,
        messageCache: cache,
      );

      blocB.execute();
      await blocB.initialHydrationFuture;
      await pumpEventQueue();

      // User B must NOT see User A's pending message
      expect(blocB.cursorPageHolder.items, isEmpty);

      // Outbox processor running for User B must NOT send User A's message
      final sentByProcessor = <String>[];
      final processorB = ChatOutboxProcessor(
        outboxStorage: outbox,
        currentUserScopeProvider: () => '202',
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required clientMessageId,
          required content,
          required conversationId,
          messageType = 'text',
        }) {
          sentByProcessor.add(clientMessageId);
        },
      );

      await processorB.processPending();
      expect(sentByProcessor, isEmpty);

      blocB.close();
    });

    test('12. Fix 1: Same-conversation-ID account switching isolates pending outbox messages per user', () async {
      final cache = ChatMessageCache();
      final outbox = InMemoryOutboxStorage();
      const conversationId = 'group-conv-same-id';

      // User A saves pending message in group
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'pending-a',
          conversationId: conversationId,
          content: 'Message from User A',
          createdAt: DateTime.now(),
          senderId: '101',
        ),
      );

      // User B saves pending message in same group
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'pending-b',
          conversationId: conversationId,
          content: 'Message from User B',
          createdAt: DateTime.now().add(const Duration(seconds: 1)),
          senderId: '202',
        ),
      );

      final repo = MockControlledHistoryRepo();

      // Check User A's view
      ChatMessageCache.userScopeResolver = () => '101';
      final blocA = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        outboxStorage: outbox,
        messageCache: cache,
      );
      blocA.execute();
      await blocA.initialHydrationFuture;
      await pumpEventQueue();

      expect(blocA.cursorPageHolder.items.length, equals(1));
      expect(blocA.cursorPageHolder.items.first.clientMessageId, equals('pending-a'));
      expect(blocA.cursorPageHolder.items.first.senderId, equals('101'));
      blocA.close();

      // Check User B's view
      ChatMessageCache.userScopeResolver = () => '202';
      final blocB = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        outboxStorage: outbox,
        messageCache: cache,
      );
      blocB.execute();
      await blocB.initialHydrationFuture;
      await pumpEventQueue();

      expect(blocB.cursorPageHolder.items.length, equals(1));
      expect(blocB.cursorPageHolder.items.first.clientMessageId, equals('pending-b'));
      expect(blocB.cursorPageHolder.items.first.senderId, equals('202'));
      blocB.close();
    });

    test('13. Fix 1: Logout during in-flight retry halts processor and never sends old message under new user', () async {
      final outbox = InMemoryOutboxStorage();
      const conversationId = 'conv-inflight-cancel';

      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'pending-a-1',
          conversationId: conversationId,
          content: 'Msg 1 from A',
          createdAt: DateTime.now(),
          senderId: '101',
        ),
      );
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'pending-a-2',
          conversationId: conversationId,
          content: 'Msg 2 from A',
          createdAt: DateTime.now().add(const Duration(seconds: 1)),
          senderId: '101',
        ),
      );

      String activeUser = '101';
      final sentMessages = <String>[];
      late ChatOutboxProcessor processor;

      processor = ChatOutboxProcessor(
        outboxStorage: outbox,
        currentUserScopeProvider: () => activeUser,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required clientMessageId,
          required content,
          required conversationId,
          messageType = 'text',
        }) {
          sentMessages.add('$clientMessageId by $activeUser');
          if (clientMessageId == 'pending-a-1') {
            // Simulate logout and account switch during in-flight send
            processor.cancel();
            activeUser = '202';
          }
        },
      );

      await processor.processPending();

      // Only the first message was sent; processor halted immediately and did not send pending-a-2 under user 202
      expect(sentMessages, equals(['pending-a-1 by 101']));
      expect(processor.isProcessing, isFalse);
    });

    test('14. Fix 1: Same-user restart/recovery preserves and recovers pending outbox messages', () async {
      final cache = ChatMessageCache();
      final outbox = InMemoryOutboxStorage();
      const conversationId = 'conv-recover-same-user';

      // User A (101) creates pending message
      await outbox.save(
        PendingOutboxMessage(
          clientMessageId: 'pending-persist-1',
          conversationId: conversationId,
          content: 'Important draft',
          createdAt: DateTime.now(),
          senderId: '101',
        ),
      );

      // User A logs out (AuthSession.clear called, but storage preserves scoped messages)
      await AuthSession.clear();

      // User A logs back in
      ChatMessageCache.userScopeResolver = () => '101';

      final repo = MockControlledHistoryRepo();
      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        outboxStorage: outbox,
        messageCache: cache,
      );

      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // Pending message is successfully recovered for User A
      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.clientMessageId, equals('pending-persist-1'));
      expect(bloc.cursorPageHolder.items.first.senderId, equals('101'));

      bloc.close();
    });

    test('15. Fix 2: WebSocket message during in-flight HTTP request survives reconciliation and persists', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-concurrent-ws';

      final networkCompleter = Completer<CursorPaginationResponse<ChatMessage>>();
      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) =>
            networkCompleter.future,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        messageCache: cache,
      );

      // 1. Start initial HTTP fetch
      bloc.execute();
      expect(bloc.isInitialLoading, isTrue);
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // 2. Deliver a new message over WebSocket while HTTP is pending
      final wsMsg = createMessage(
        id: '200',
        clientMessageId: 'ws-client-200',
        content: 'Concurrent live WebSocket message',
        senderId: '303', // From another user
        isMine: false,
        sentAt: DateTime.utc(2026, 10, 10, 12, 5),
      );
      await bloc.handleNewMessage(message: wsMsg);

      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.id, equals('200'));

      // 3. Complete HTTP response with older server history (does NOT include message 200)
      final serverMsg1 = createMessage(
        id: '150',
        clientMessageId: 'server-150',
        content: 'Server history 150',
        sentAt: DateTime.utc(2026, 10, 10, 12, 0),
      );
      final serverMsg2 = createMessage(
        id: '140',
        clientMessageId: 'server-140',
        content: 'Server history 140',
        sentAt: DateTime.utc(2026, 10, 10, 11, 55),
      );

      networkCompleter.complete(
        CursorPaginationResponse(
          data: [serverMsg1, serverMsg2],
          hasMore: false,
          fromJsonFactory: ChatMessage.fromJson,
          toJsonFactory: (m) => m.toJson(),
        ),
      );

      await pumpEventQueue();

      // 4. Verify the WebSocket message remains in memory and visible state
      expect(bloc.cursorPageHolder.items.length, equals(3));
      expect(bloc.cursorPageHolder.items[0].id, equals('200'));
      expect(bloc.cursorPageHolder.items[0].message, equals('Concurrent live WebSocket message'));
      expect(bloc.cursorPageHolder.items[1].id, equals('150'));
      expect(bloc.cursorPageHolder.items[2].id, equals('140'));

      // 5. Verify the WebSocket message is persisted into cache along with server history
      await pumpEventQueue();
      final cached = await cache.getMessages(conversationId: conversationId);
      expect(cached, isNotNull);
      expect(cached!.messages.length, equals(3));
      expect(cached.messages[0].id, equals('200'));
      expect(cached.messages[1].id, equals('150'));
      expect(cached.messages[2].id, equals('140'));

      bloc.close();
    });

    test('16. Fix 2: HTTP response containing the same message already delivered over WebSocket merges without duplicate', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-dedupe-ws-http';

      final networkCompleter = Completer<CursorPaginationResponse<ChatMessage>>();
      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) =>
            networkCompleter.future,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        messageCache: cache,
      );

      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // WebSocket delivers message 105
      final wsMsg = createMessage(
        id: '105',
        clientMessageId: 'c-105',
        content: 'Delivered via WebSocket',
        isDelivered: true,
        isSeen: false,
      );
      await bloc.handleNewMessage(message: wsMsg);

      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.id, equals('105'));

      // HTTP response returns same message 105 (with updated seen status) plus message 104
      final httpMsg105 = createMessage(
        id: '105',
        clientMessageId: 'c-105',
        content: 'Delivered via WebSocket',
        isDelivered: true,
        isSeen: true,
      );
      final httpMsg104 = createMessage(
        id: '104',
        clientMessageId: 'c-104',
        content: 'Older message',
        isDelivered: true,
        isSeen: true,
      );

      networkCompleter.complete(
        CursorPaginationResponse(
          data: [httpMsg105, httpMsg104],
          hasMore: false,
          fromJsonFactory: ChatMessage.fromJson,
          toJsonFactory: (m) => m.toJson(),
        ),
      );

      await pumpEventQueue();

      // Exactly 2 items, no duplicate 105, monotonic seen status preserved
      expect(bloc.cursorPageHolder.items.length, equals(2));
      expect(bloc.cursorPageHolder.items[0].id, equals('105'));
      expect(bloc.cursorPageHolder.items[0].isSeen, isTrue);
      expect(bloc.cursorPageHolder.items[1].id, equals('104'));

      bloc.close();
    });

    test('17. Fix 2: Cached messages outside server page 1 are not dropped upon initial reconciliation', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-cached-multi-page';

      // Pre-seed cache with 4 messages: 40, 30, 20, 10
      final m40 = createMessage(id: '40', content: 'Msg 40', sentAt: DateTime.utc(2026, 10, 10, 10, 40));
      final m30 = createMessage(id: '30', content: 'Msg 30', sentAt: DateTime.utc(2026, 10, 10, 10, 30));
      final m20 = createMessage(id: '20', content: 'Msg 20', sentAt: DateTime.utc(2026, 10, 10, 10, 20));
      final m10 = createMessage(id: '10', content: 'Msg 10', sentAt: DateTime.utc(2026, 10, 10, 10, 10));

      await cache.saveMessages(
        conversationId: conversationId,
        messages: [m40, m30, m20, m10],
        targetUserScope: 'guest',
      );

      // Server only returns the latest page with 40 and 30
      final networkCompleter = Completer<CursorPaginationResponse<ChatMessage>>();
      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) =>
            networkCompleter.future,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        messageCache: cache,
      );

      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // Before HTTP completes, all 4 cached messages are visible
      expect(bloc.cursorPageHolder.items.length, equals(4));

      // Server response arrives with only the newest page (messages 40 and 30)
      networkCompleter.complete(
        CursorPaginationResponse(
          data: [m40, m30],
          hasMore: true,
          nextCursor: '30',
          fromJsonFactory: ChatMessage.fromJson,
          toJsonFactory: (m) => m.toJson(),
        ),
      );

      await pumpEventQueue();

      // Older cached messages 20 and 10 MUST NOT be dropped!
      expect(bloc.cursorPageHolder.items.length, equals(4));
      expect(bloc.cursorPageHolder.items[0].id, equals('40'));
      expect(bloc.cursorPageHolder.items[1].id, equals('30'));
      expect(bloc.cursorPageHolder.items[2].id, equals('20'));
      expect(bloc.cursorPageHolder.items[3].id, equals('10'));

      // Cache also retains all 4 messages
      final cached = await cache.getMessages(conversationId: conversationId);
      expect(cached!.messages.length, equals(4));

      bloc.close();
    });

    test('18. Fix 1: Processor cancelled or user switched during awaited getMessagesForConversation halts immediately and never transmits old user message', () async {
      final pausableOutbox = PausableOutboxStorage();
      const conversationId = 'conv-mid-await-cancel';

      await pausableOutbox.save(
        PendingOutboxMessage(
          clientMessageId: 'pending-a-mid-await',
          conversationId: conversationId,
          content: 'Pending from User A',
          createdAt: DateTime.now(),
          senderId: '101',
        ),
      );

      String activeUser = '101';
      final sentMessages = <String>[];
      final processor = ChatOutboxProcessor(
        outboxStorage: pausableOutbox,
        currentUserScopeProvider: () => activeUser,
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required clientMessageId,
          required content,
          required conversationId,
          messageType = 'text',
        }) {
          sentMessages.add('$clientMessageId by $activeUser');
        },
      );

      final pauseCompleter = Completer<void>();
      final startedCompleter = Completer<void>();
      pausableOutbox.pauseGetMessagesCompleter = pauseCompleter;
      pausableOutbox.onGetMessagesStartedCompleter = startedCompleter;

      // Start processing as User A without conversationIdFilter so getAllMessages fetches snapshot first
      final processFuture = processor.processPending();

      // Wait until getMessagesForConversation is paused inside the processor loop
      await startedCompleter.future;

      // While storage call is suspended, cancel processor and switch active user to User B
      processor.cancel();
      activeUser = '202';

      // Resume storage call
      pauseCompleter.complete();
      await processFuture;

      // Assert that User A's pending message was NEVER transmitted under User B
      expect(sentMessages, isEmpty);
      expect(processor.isProcessing, isFalse);

      // Verify same-user retry/recovery remains intact afterwards:
      activeUser = '101';
      pausableOutbox.pauseGetMessagesCompleter = null;
      pausableOutbox.onGetMessagesStartedCompleter = null;
      await processor.processPending();

      expect(sentMessages, equals(['pending-a-mid-await by 101']));
    });

    test('19. Fix 2: Interleaved message IDs between server and cache are sorted canonically (ORDER BY id DESC)', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-interleaved-order';

      // Cache has message with ID 95
      final m95 = createMessage(
        id: '95',
        clientMessageId: 'c-95',
        content: 'Cached 95',
        sentAt: DateTime(2026, 1, 1, 10, 5),
      );
      await cache.saveMessages(
        conversationId: conversationId,
        messages: [m95],
        targetUserScope: 'guest',
      );

      // Server returns page 1 with IDs 100 and 90 (surrounding 95)
      final m100 = createMessage(
        id: '100',
        clientMessageId: 'c-100',
        content: 'Server 100',
        sentAt: DateTime(2026, 1, 1, 10, 10),
      );
      final m90 = createMessage(
        id: '90',
        clientMessageId: 'c-90',
        content: 'Server 90',
        sentAt: DateTime(2026, 1, 1, 10, 0),
      );

      final networkCompleter = Completer<CursorPaginationResponse<ChatMessage>>();
      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) =>
            networkCompleter.future,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        messageCache: cache,
      );

      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // Before server response, cached message 95 is visible
      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.id, equals('95'));

      // Server responds with 100 and 90
      networkCompleter.complete(
        CursorPaginationResponse(
          data: [m100, m90],
          hasMore: true,
          nextCursor: '90',
          fromJsonFactory: ChatMessage.fromJson,
          toJsonFactory: (m) => m.toJson(),
        ),
      );
      await pumpEventQueue();

      // The merged list must strictly respect canonical descending order: 100, 95, 90
      final ids = bloc.cursorPageHolder.items.map((m) => m.id).toList();
      expect(ids, equals(['100', '95', '90']));

      bloc.close();
    });

    test('20. Fix 2: Follow-up older-page pagination uses server cursor before_id and merges contiguous history without duplicates or gaps', () async {
      final cache = ChatMessageCache();
      const conversationId = 'conv-pagination-contiguous';

      // Cache initially has message 95 and older cached message 20
      final m95 = createMessage(
        id: '95',
        clientMessageId: 'c-95',
        content: 'Cached 95',
        sentAt: DateTime(2026, 1, 1, 10, 5),
      );
      final m20 = createMessage(
        id: '20',
        clientMessageId: 'c-20',
        content: 'Cached 20',
        sentAt: DateTime(2026, 1, 1, 9, 20),
      );
      await cache.saveMessages(
        conversationId: conversationId,
        messages: [m95, m20],
        targetUserScope: 'guest',
      );

      final m100 = createMessage(
        id: '100',
        clientMessageId: 'c-100',
        content: 'Server 100',
        sentAt: DateTime(2026, 1, 1, 10, 10),
      );
      final m90 = createMessage(
        id: '90',
        clientMessageId: 'c-90',
        content: 'Server 90',
        sentAt: DateTime(2026, 1, 1, 10, 0),
      );

      final page1Completer = Completer<CursorPaginationResponse<ChatMessage>>();
      final page2Completer = Completer<CursorPaginationResponse<ChatMessage>>();
      final capturedBeforeIds = <String?>[];

      final repo = MockControlledHistoryRepo(
        onGetMessages: (convId, {beforeId, limit = 20, sinceId}) {
          capturedBeforeIds.add(beforeId);
          if (capturedBeforeIds.length == 1) {
            return page1Completer.future;
          }
          return page2Completer.future;
        },
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: conversationId,
        repository: repo,
        messageCache: cache,
      );

      // Initial hydration and fetch
      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      expect(capturedBeforeIds.length, equals(1));
      expect(capturedBeforeIds.first, isNull); // Initial page has beforeId == null

      // Server returns page 1: [100, 90] with nextCursor: '90'
      page1Completer.complete(
        CursorPaginationResponse(
          data: [m100, m90],
          hasMore: true,
          nextCursor: '90',
          fromJsonFactory: ChatMessage.fromJson,
          toJsonFactory: (m) => m.toJson(),
        ),
      );
      await pumpEventQueue();

      // Verify merged state has canonical descending order: 100, 95, 90, 20
      expect(
        bloc.cursorPageHolder.items.map((m) => m.id).toList(),
        equals(['100', '95', '90', '20']),
      );
      expect(bloc.cursorPageHolder.nextCursor, equals('90'));

      // Now trigger older-page pagination (scrolling up)
      bloc.add(
        FetchDataWithQueryEvent(
          query: {},
          clearPageWithNewData: false,
        ),
      );
      await pumpEventQueue();

      // Verify pagination request used '90' (oldest contiguous server message), NOT '20' or an out-of-order cached tail
      expect(capturedBeforeIds.length, equals(2));
      expect(capturedBeforeIds[1], equals('90'));

      // Server returns page 2 with [80, 20] (20 overlaps with cache), hasMore: false
      final m80 = createMessage(
        id: '80',
        clientMessageId: 'c-80',
        content: 'Server 80',
        sentAt: DateTime(2026, 1, 1, 9, 50),
      );
      final m20Server = createMessage(
        id: '20',
        clientMessageId: 'c-20',
        content: 'Server 20 updated',
        sentAt: DateTime(2026, 1, 1, 9, 20),
        isSeen: true,
      );

      page2Completer.complete(
        CursorPaginationResponse(
          data: [m80, m20Server],
          hasMore: false,
          nextCursor: null,
          fromJsonFactory: ChatMessage.fromJson,
          toJsonFactory: (m) => m.toJson(),
        ),
      );
      await pumpEventQueue();

      // Final list has no duplicates, canonical descending order: 100, 95, 90, 80, 20
      final finalIds = bloc.cursorPageHolder.items.map((m) => m.id).toList();
      expect(finalIds, equals(['100', '95', '90', '80', '20']));
      // Overlapping message 20 merged monotonic status (isSeen == true)
      final merged20 = bloc.cursorPageHolder.items.firstWhere((m) => m.id == '20');
      expect(merged20.isSeen, isTrue);

      bloc.close();
    });
  });
}
