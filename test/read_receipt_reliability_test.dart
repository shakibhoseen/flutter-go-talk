import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_flutter_go/core/db/local_cache/chat_message_cache.dart';
import 'package:whatsapp_flutter_go/core/db/local_cache/hive_initializer.dart';
import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/chat_seen_ack_manager.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_sync_coordinator.dart';
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

class FakeTestSocketService extends ChatSocketService {
  FakeTestSocketService() : super.testInstance();

  bool connected = false;
  final List<Map<String, dynamic>> dispatchedSeenAcks = [];

  @override
  bool get isConnected => connected;

  @override
  bool sendSeenAck({
    required String conversationId,
    required String messageId,
    int senderId = 0,
  }) {
    if (!connected) {
      return false;
    }
    dispatchedSeenAcks.add({
      'conversation_id': conversationId,
      'message_id': messageId,
      'sender_id': senderId,
    });
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ChatMessageCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('receipt_test_');
    SharedPreferences.setMockInitialValues({});
    HiveInitializer.resetForTesting();
    cache = ChatMessageCache();
    cache.resetForTesting();
    ChatMessageCache.userScopeResolver = () => 'user-101';
    await HiveInitializer.ensureInitialized(tempDir.path);
  });

  tearDown(() async {
    await AuthSession.clear();
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    HiveInitializer.resetForTesting();
    cache.resetForTesting();
  });

  ChatMessage createMessage({
    required String id,
    String? clientMessageId,
    required String content,
    String senderId = '101',
    String conversationId = 'conv-1',
    DateTime? sentAt,
    bool isMine = true,
    bool isDelivered = false,
    bool isSeen = false,
  }) {
    final now = sentAt ?? DateTime.now();
    return ChatMessage(
      id: id,
      clientMessageId: clientMessageId,
      senderId: senderId,
      receiverId: conversationId,
      message: content,
      sentAt: now,
      messageType: 'text',
      isMine: isMine,
      isDelivered: isDelivered,
      isSeen: isSeen,
      timeStamp: TimeStamp.fromDatePublish(now.millisecondsSinceEpoch),
    );
  }

  group('Phase 2B: Read Receipts & Watermark Persistence', () {
    test(
        'Test A: Watermark preservation when saving messages with watermarks == null (and explicit clear)',
        () async {
      final m1 = createMessage(id: '10', content: 'Hello');
      final initialWatermarks = {
        '10': {
          'users': [
            {'user_id': 201, 'name': 'Bob', 'avatar_url': 'bob.png'}
          ],
          'count': 1,
        }
      };

      // 1. Initial save with watermarks
      await cache.saveMessages(
        conversationId: 'conv-1',
        messages: [m1],
        watermarks: initialWatermarks,
        targetUserScope: 'user-101',
      );

      final loaded1 = await cache.getMessages(
        conversationId: 'conv-1',
        targetUserScope: 'user-101',
      );
      expect(loaded1, isNotNull);
      expect(loaded1!.watermarks, isNotNull);

      // 2. Save newer message with watermarks == null (default clearWatermarks = false)
      final m2 = createMessage(id: '11', content: 'World');
      await cache.saveMessages(
        conversationId: 'conv-1',
        messages: [m2, m1],
        watermarks: null,
        targetUserScope: 'user-101',
      );

      final loaded2 = await cache.getMessages(
        conversationId: 'conv-1',
        targetUserScope: 'user-101',
      );
      expect(loaded2, isNotNull);
      // BUG 1 Check: Must NOT be overwritten with null
      expect(
        loaded2!.watermarks,
        isNotNull,
        reason: 'Watermarks must be preserved when saveMessages is called with null',
      );
      final wmMap = Map<String, dynamic>.from(loaded2.watermarks as Map);
      expect(wmMap['10'], isNotNull);

      // 3. Explicit clearWatermarks: true MUST wipe watermarks
      await cache.saveMessages(
        conversationId: 'conv-1',
        messages: [m2, m1],
        clearWatermarks: true,
        targetUserScope: 'user-101',
      );

      final loaded3 = await cache.getMessages(
        conversationId: 'conv-1',
        targetUserScope: 'user-101',
      );
      expect(loaded3, isNotNull);
      expect(loaded3!.watermarks, isNull, reason: 'clearWatermarks: true must clear watermarks');
    });

    test(
        'Test B: Live member_read_watermark persistence and offline recovery across Hive close/reopen',
        () async {
      final m50 = createMessage(
        id: '50',
        content: 'Important msg',
        senderId: '101',
        isMine: true,
        isDelivered: true,
        isSeen: false,
      );

      await cache.saveMessages(
        conversationId: 'conv-1',
        messages: [m50],
        targetUserScope: 'user-101',
      );

      final repo = MockControlledHistoryRepo(
        onGetMessages: (_, {beforeId, limit = 20, sinceId}) async {
          return CursorPaginationResponse(
            data: [m50],
            hasMore: false,
            fromJsonFactory: ChatMessage.fromJson,
            toJsonFactory: (m) => m.toJson(),
          );
        },
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        isGroup: false,
        repository: repo,
        messageCache: cache,
      );

      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // Receive live member_read_watermark
      bloc.handleMemberWatermark(
        userId: 202,
        messageId: 50,
        profile: const ReadReceiptUser(
          userId: 202,
          name: 'Charlie',
          avatarUrl: 'charlie.png',
        ),
      );
      await pumpEventQueue();

      // Verify in-memory state updated
      expect(bloc.cursorPageHolder.items.first.isSeen, isTrue);
      expect(bloc.getWatermarkCount('50'), equals(1));
      expect(bloc.getWatermarkUsers('50').first.name, equals('Charlie'));

      bloc.close();

      // Simulate full app restart offline: Close Hive and reopen
      await Hive.close();
      await HiveInitializer.ensureInitialized(tempDir.path);

      final restartedCache = ChatMessageCache();
      restartedCache.resetForTesting();

      final offlineRepo = MockControlledHistoryRepo(
        onGetMessages: (_, {beforeId, limit = 20, sinceId}) =>
            throw Exception('Network unreachable offline'),
      );

      final newBloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        isGroup: false,
        repository: offlineRepo,
        messageCache: restartedCache,
      );

      newBloc.execute();
      await newBloc.initialHydrationFuture;
      await pumpEventQueue();

      // BUG 2 Check: Restored from cache must preserve member watermark and seen status!
      expect(newBloc.cursorPageHolder.items.isNotEmpty, isTrue);
      final restoredM50 = newBloc.cursorPageHolder.items.first;
      expect(restoredM50.id, equals('50'));
      expect(restoredM50.isSeen, isTrue, reason: 'Restored message must preserve isSeen');
      expect(
        newBloc.getWatermarkCount('50'),
        equals(1),
        reason: 'Restored bloc must preserve watermark count',
      );
      final users = newBloc.getWatermarkUsers('50');
      expect(users.isNotEmpty, isTrue);
      expect(users.first.name, equals('Charlie'));

      newBloc.close();
    });

    test(
        'Test C: Live status_updated persistence and offline recovery across Hive close/reopen, with monotonicity check',
        () async {
      final m100 = createMessage(
        id: '100',
        content: 'Msg 100',
        senderId: '101',
        isMine: true,
        isDelivered: false,
        isSeen: false,
      );
      final m90 = createMessage(
        id: '90',
        content: 'Msg 90',
        senderId: '101',
        isMine: true,
        isDelivered: false,
        isSeen: false,
      );

      await cache.saveMessages(
        conversationId: 'conv-1',
        messages: [m100, m90],
        targetUserScope: 'user-101',
      );

      final repo = MockControlledHistoryRepo(
        onGetMessages: (_, {beforeId, limit = 20, sinceId}) async {
          return CursorPaginationResponse(
            data: [m100, m90],
            hasMore: false,
            fromJsonFactory: ChatMessage.fromJson,
            toJsonFactory: (m) => m.toJson(),
          );
        },
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: repo,
        messageCache: cache,
      );

      bloc.execute();
      await bloc.initialHydrationFuture;
      await pumpEventQueue();

      // 1. Live delivered status update for message 100 (and up to 100, so m90 also delivered)
      bloc.handleStatusUpdated(
        statusMessageId: '100',
        status: 'delivered',
      );
      await pumpEventQueue();

      expect(bloc.cursorPageHolder.items.firstWhere((m) => m.id == '100').isDelivered, isTrue);
      expect(bloc.cursorPageHolder.items.firstWhere((m) => m.id == '100').isSeen, isFalse);
      expect(bloc.cursorPageHolder.items.firstWhere((m) => m.id == '90').isDelivered, isTrue);

      // 2. Live seen status update for message 90
      bloc.handleStatusUpdated(
        statusMessageId: '90',
        status: 'seen',
      );
      await pumpEventQueue();

      expect(bloc.cursorPageHolder.items.firstWhere((m) => m.id == '90').isSeen, isTrue);
      expect(bloc.cursorPageHolder.items.firstWhere((m) => m.id == '90').isDelivered, isTrue);

      // 3. Monotonicity check: An older or redundant delivered status must never downgrade isSeen
      bloc.handleStatusUpdated(
        statusMessageId: '90',
        status: 'delivered',
      );
      await pumpEventQueue();
      expect(
        bloc.cursorPageHolder.items.firstWhere((m) => m.id == '90').isSeen,
        isTrue,
        reason: 'Delivered event must never downgrade seen status',
      );

      bloc.close();

      // 4. Simulate app death: Close Hive and reopen
      await Hive.close();
      await HiveInitializer.ensureInitialized(tempDir.path);

      final restartedCache = ChatMessageCache();
      restartedCache.resetForTesting();

      final offlineRepo = MockControlledHistoryRepo(
        onGetMessages: (_, {beforeId, limit = 20, sinceId}) =>
            throw Exception('Network unreachable offline'),
      );

      final newBloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: offlineRepo,
        messageCache: restartedCache,
      );

      newBloc.execute();
      await newBloc.initialHydrationFuture;
      await pumpEventQueue();

      // BUG 3 Check: Both messages must have their live status changes restored offline!
      final restoredM100 = newBloc.cursorPageHolder.items.firstWhere((m) => m.id == '100');
      final restoredM90 = newBloc.cursorPageHolder.items.firstWhere((m) => m.id == '90');

      expect(restoredM100.isDelivered, isTrue);
      expect(restoredM100.isSeen, isFalse);
      expect(restoredM90.isDelivered, isTrue);
      expect(
        restoredM90.isSeen,
        isTrue,
        reason: 'Live seen status must be persisted and restored offline',
      );

      newBloc.close();
    });

    test(
        'Test D: Online socket write (dispatch) does NOT delete pending intent before server confirmation; manager/app restart before server confirmation retries latest read watermark on reconnect',
        () async {
      final fakeSocket = FakeTestSocketService();
      final seenManager = ChatSeenAckManager(
        socketService: fakeSocket,
        messageCache: cache,
        userScopeResolver: () => 'user-101',
      );

      // 1. Socket is online, user views message 150
      fakeSocket.connected = true;
      await seenManager.onMessageSeen(
        conversationId: 'conv-1',
        messageId: 150,
        senderId: 201,
      );

      // Dispatch succeeded at local socket level (sink.add was called)
      expect(fakeSocket.dispatchedSeenAcks.length, equals(1));
      expect(fakeSocket.dispatchedSeenAcks.first['message_id'], equals('150'));

      // KEY AUDIT CHECK: Socket write is local dispatch, NOT server confirmation!
      // Pending intent MUST still be preserved in durable storage in case app crashes before Go server commits.
      final pendingBeforeRestart = await cache.getPendingSeenAck(
        conversationId: 'conv-1',
        targetUserScope: 'user-101',
      );
      expect(
        pendingBeforeRestart,
        isNotNull,
        reason: 'Local socket write must not delete pending intent before server confirmation',
      );
      expect(pendingBeforeRestart!.messageId, equals(150));

      // 2. Simulate app crash / restart before server confirmed processing:
      await Hive.close();
      await HiveInitializer.ensureInitialized(tempDir.path);

      final restartedCache = ChatMessageCache();
      restartedCache.resetForTesting();

      final restartedSocket = FakeTestSocketService();
      final restartedManager = ChatSeenAckManager(
        socketService: restartedSocket,
        messageCache: restartedCache,
        userScopeResolver: () => 'user-101',
      );

      // 3. Reconnect occurs: unconfirmed latest read watermark MUST be retried across new socket!
      restartedSocket.connected = true;
      await restartedManager.retryPendingAcks();

      expect(
        restartedSocket.dispatchedSeenAcks.length,
        equals(1),
        reason: 'Latest read watermark must be retried after app restart if not yet confirmed by server',
      );
      expect(restartedSocket.dispatchedSeenAcks.first['message_id'], equals('150'));

      // 4. Server authoritative watermark arrives (e.g. from delta sync / getMessages)
      await restartedManager.confirmServerWatermark(
        conversationId: 'conv-1',
        serverMessageId: 150,
      );

      // Now that server confirmed processing, pending intent is safely retired from disk!
      final pendingAfterServerConfirm = await restartedCache.getPendingSeenAck(
        conversationId: 'conv-1',
        targetUserScope: 'user-101',
      );
      expect(
        pendingAfterServerConfirm,
        isNull,
        reason: 'Pending intent must be cleared from disk after server confirms watermark',
      );

      // Future reconnects will not re-dispatch conv-1
      restartedSocket.dispatchedSeenAcks.clear();
      restartedManager.onSocketReconnected();
      await restartedManager.retryPendingAcks();
      expect(restartedSocket.dispatchedSeenAcks, isEmpty);
    });

    test(
        'Test E: Pending ACK for conversation A is retried when reconnect happens while conversation B is open',
        () async {
      final fakeSocket = FakeTestSocketService();
      final seenManager = ChatSeenAckManager(
        socketService: fakeSocket,
        messageCache: cache,
        userScopeResolver: () => 'user-101',
      );

      // 1. Offline view in conversation A
      fakeSocket.connected = false;
      await seenManager.onMessageSeen(
        conversationId: 'conv-A',
        messageId: 50,
        senderId: 201,
      );

      expect(fakeSocket.dispatchedSeenAcks, isEmpty);

      // 2. User opens conversation B, and reconnect occurs
      // ChatSyncCoordinator runs reconnect, which calls retryPendingAcks() globally
      fakeSocket.connected = true;
      await seenManager.retryPendingAcks();

      // Conversation A's pending ACK MUST be dispatched even though Conversation B was the active screen
      expect(fakeSocket.dispatchedSeenAcks.length, equals(1));
      expect(fakeSocket.dispatchedSeenAcks.first['conversation_id'], equals('conv-A'));
      expect(fakeSocket.dispatchedSeenAcks.first['message_id'], equals('50'));
    });

    test(
        'Test F: Multiple offline reads coalesce to the highest message ID separately per conversation',
        () async {
      final fakeSocket = FakeTestSocketService();
      final seenManager = ChatSeenAckManager(
        socketService: fakeSocket,
        messageCache: cache,
        userScopeResolver: () => 'user-101',
      );

      fakeSocket.connected = false;

      // In conv-1: reads 100, then 120, then 115 (out of order view)
      await seenManager.onMessageSeen(conversationId: 'conv-1', messageId: 100, senderId: 201);
      await seenManager.onMessageSeen(conversationId: 'conv-1', messageId: 120, senderId: 201);
      await seenManager.onMessageSeen(conversationId: 'conv-1', messageId: 115, senderId: 201);

      // In conv-2: reads 40, then 80
      await seenManager.onMessageSeen(conversationId: 'conv-2', messageId: 40, senderId: 202);
      await seenManager.onMessageSeen(conversationId: 'conv-2', messageId: 80, senderId: 202);

      // Reconnect
      fakeSocket.connected = true;
      await seenManager.retryPendingAcks();

      // Only conv-1: 120 and conv-2: 80 must be dispatched (coalesced to highest per conversation)
      expect(fakeSocket.dispatchedSeenAcks.length, equals(2));
      final conv1Ack = fakeSocket.dispatchedSeenAcks.firstWhere((a) => a['conversation_id'] == 'conv-1');
      final conv2Ack = fakeSocket.dispatchedSeenAcks.firstWhere((a) => a['conversation_id'] == 'conv-2');

      expect(conv1Ack['message_id'], equals('120'));
      expect(conv2Ack['message_id'], equals('80'));
    });

    test(
        'Test G: Logout and account switch isolates pending ACKs and prevents old-user ACKs from being sent',
        () async {
      final fakeSocket = FakeTestSocketService();
      final seenManagerUserA = ChatSeenAckManager(
        socketService: fakeSocket,
        messageCache: cache,
        userScopeResolver: () => 'user-A',
      );

      fakeSocket.connected = false;
      await seenManagerUserA.onMessageSeen(
        conversationId: 'conv-1',
        messageId: 500,
        senderId: 201,
      );

      // User A logs out: AuthSession.clear() resets manager and clears message cache
      await AuthSession.clear();

      // User B logs in
      final seenManagerUserB = ChatSeenAckManager(
        socketService: fakeSocket,
        messageCache: cache,
        userScopeResolver: () => 'user-B',
      );

      fakeSocket.connected = true;
      fakeSocket.dispatchedSeenAcks.clear();

      await seenManagerUserB.retryPendingAcks();

      expect(
        fakeSocket.dispatchedSeenAcks,
        isEmpty,
        reason: "User B must never dispatch User A's pending seen ACKs",
      );
    });

    test(
        'Test H: Repeated reconnect triggers within same connection do not cause an unbounded retry loop',
        () async {
      final fakeSocket = FakeTestSocketService();
      final seenManager = ChatSeenAckManager(
        socketService: fakeSocket,
        messageCache: cache,
        userScopeResolver: () => 'user-101',
      );

      fakeSocket.connected = false;
      await seenManager.onMessageSeen(
        conversationId: 'conv-1',
        messageId: 200,
        senderId: 201,
      );

      fakeSocket.connected = true;

      // First reconnect triggers retry
      await seenManager.retryPendingAcks();
      expect(fakeSocket.dispatchedSeenAcks.length, equals(1));
      expect(fakeSocket.dispatchedSeenAcks.first['message_id'], equals('200'));

      // Subsequent 5 redundant triggers (e.g. duplicate reconnect callbacks, delta sync completions)
      for (var i = 0; i < 5; i++) {
        await seenManager.retryPendingAcks();
      }

      // Assert count remains exactly 1: no unbounded loop, no duplicate frames on the same connection
      expect(
        fakeSocket.dispatchedSeenAcks.length,
        equals(1),
        reason: 'Redundant retry calls on same connection must not re-dispatch already sent frame',
      );
    });

    test(
        'Test I: Stale server watermark confirmation cannot clear a newer pending ACK created concurrently',
        () async {
      final fakeSocket = FakeTestSocketService();
      final seenManager = ChatSeenAckManager(
        socketService: fakeSocket,
        messageCache: cache,
        userScopeResolver: () => 'user-101',
      );

      // User saw message 100 initially
      fakeSocket.connected = false;
      await seenManager.onMessageSeen(
        conversationId: 'conv-1',
        messageId: 100,
        senderId: 201,
      );

      // Now user reads a newer message 110 concurrently
      await seenManager.onMessageSeen(
        conversationId: 'conv-1',
        messageId: 110,
        senderId: 201,
      );

      // A stale confirmation arrives for earlier message 100
      await seenManager.confirmServerWatermark(
        conversationId: 'conv-1',
        serverMessageId: 100,
      );

      // Stale confirmation for 100 MUST NOT clear the newer pending ACK 110!
      final pending = await cache.getPendingSeenAck(
        conversationId: 'conv-1',
        targetUserScope: 'user-101',
      );
      expect(pending, isNotNull, reason: 'Pending intent must not be wiped by stale watermark confirmation');
      expect(pending!.messageId, equals(110));

      // Now an authoritative confirmation arrives for message 110 (or higher, e.g. 115)
      await seenManager.confirmServerWatermark(
        conversationId: 'conv-1',
        serverMessageId: 110,
      );

      final pendingAfterValidConfirm = await cache.getPendingSeenAck(
        conversationId: 'conv-1',
        targetUserScope: 'user-101',
      );
      expect(pendingAfterValidConfirm, isNull, reason: 'Authoritative confirmation up to 110 must clear it');
    });

    test(
        'Test J: Active conversation delta sync failure does not block retrying pending ACKs for other conversations',
        () async {
      final fakeSocket = FakeTestSocketService();
      final seenManager = ChatSeenAckManager(
        socketService: fakeSocket,
        messageCache: cache,
        userScopeResolver: () => 'user-101',
      );

      // Conversation A has a pending read ACK
      fakeSocket.connected = false;
      await seenManager.onMessageSeen(
        conversationId: 'conv-A',
        messageId: 88,
        senderId: 201,
      );

      // Set up an active bloc for conversation B whose delta sync will FAIL
      final failingRepo = MockControlledHistoryRepo(
        onGetMessages: (_, {beforeId, limit = 20, sinceId}) =>
            throw Exception('Delta sync failed for conv-B'),
      );
      final activeBlocB = InboxMessageListCursorBloc(
        conversationId: 'conv-B',
        repository: failingRepo,
        messageCache: cache,
      );

      // Hydrate with an existing message so syncMissedMessages actually attempts a network call
      activeBlocB.cursorPageHolder.items = [
        createMessage(id: '10', content: 'Existing B msg'),
      ];

      final coordinator = ChatSyncCoordinator(
        socketService: fakeSocket,
        seenAckManager: seenManager,
      );
      coordinator.registerActiveBloc(activeBlocB);

      // Socket reconnects
      fakeSocket.connected = true;
      final handleResult = await coordinator.handleReconnect();

      // Delta sync for conv-B failed (so handleReconnect returns false for outbox safety)
      expect(handleResult, isFalse);

      // BUT pending ACK for conversation A MUST still be retried across the connected socket!
      expect(
        fakeSocket.dispatchedSeenAcks.length,
        equals(1),
        reason: 'Pending ACK for conv-A must still be retried even if conv-B delta sync fails',
      );
      expect(fakeSocket.dispatchedSeenAcks.first['conversation_id'], equals('conv-A'));
      expect(fakeSocket.dispatchedSeenAcks.first['message_id'], equals('88'));

      activeBlocB.close();
    });
  });
}
