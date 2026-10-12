import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_flutter_go/core/db/local_cache/chat_message_cache.dart';
import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/home/data/http_chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';
import 'package:whatsapp_flutter_go/feature/login/model/login_response.dart';

class MockTestChatSocketService extends ChatSocketService {
  MockTestChatSocketService({bool connected = true}) : super.testInstance() {
    connectionState.value =
        connected ? SocketConnectionState.connected : SocketConnectionState.disconnected;
  }

  final List<Map<String, dynamic>> dispatchedDeliveredAcks = [];
  bool shouldFailSend = false;

  void setConnected(bool connected) {
    connectionState.value =
        connected ? SocketConnectionState.connected : SocketConnectionState.disconnected;
  }

  @override
  bool get isConnected => connectionState.value == SocketConnectionState.connected;

  @override
  bool sendDeliveredAck({
    required String conversationId,
    required String messageId,
    int senderId = 0,
  }) {
    if (!isConnected || shouldFailSend) {
      return false;
    }
    dispatchedDeliveredAcks.add({
      'conversation_id': conversationId,
      'message_id': messageId,
      'sender_id': senderId,
    });
    return true;
  }
}

class MockTestChatMessageCache extends ChatMessageCache {
  MockTestChatMessageCache() : super.testInstance();

  bool saveCalled = false;
  List<ChatMessage>? savedMessages;

  @override
  Future<bool> saveMessages({
    required String conversationId,
    required List<ChatMessage> messages,
    dynamic watermarks,
    bool clearWatermarks = false,
    String? targetUserScope,
    int? sessionEpoch,
  }) async {
    final effectiveUserScope = targetUserScope ?? resolveCurrentUserScope();
    if (sessionEpoch != null && sessionEpoch != this.sessionEpoch) {
      return false;
    }
    if (resolveCurrentUserScope() != effectiveUserScope) {
      return false;
    }
    saveCalled = true;
    savedMessages = List.of(messages);
    return true;
  }
}

class FailingChatMessageCache extends ChatMessageCache {
  FailingChatMessageCache() : super.testInstance();

  @override
  Future<bool> saveMessages({
    required String conversationId,
    required List<ChatMessage> messages,
    dynamic watermarks,
    bool clearWatermarks = false,
    String? targetUserScope,
    int? sessionEpoch,
  }) async {
    throw Exception('Simulated cache storage failure');
  }
}

class SilentAbortChatMessageCache extends ChatMessageCache {
  SilentAbortChatMessageCache() : super.testInstance();

  @override
  Future<bool> saveMessages({
    required String conversationId,
    required List<ChatMessage> messages,
    dynamic watermarks,
    bool clearWatermarks = false,
    String? targetUserScope,
    int? sessionEpoch,
  }) async {
    return false;
  }
}

class MockDeltaChatRepository extends HttpChatRepository {
  final Map<int, List<ChatMessage>> pages;
  final Map<int, Map<String, dynamic>> watermarksBySinceId;
  final bool Function(int sinceId)? hasMoreCheck;
  final int? Function(int sinceId)? nextSinceIdOverride;
  final bool Function(int sinceId)? throwOnSinceId;

  MockDeltaChatRepository({
    required this.pages,
    this.watermarksBySinceId = const {},
    this.hasMoreCheck,
    this.nextSinceIdOverride,
    this.throwOnSinceId,
  });

  int callCount = 0;
  final List<int?> recordedSinceIds = [];

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  }) async {
    callCount++;
    recordedSinceIds.add(sinceId);

    if (throwOnSinceId != null && throwOnSinceId!(sinceId ?? 0)) {
      throw Exception('Simulated network error for sinceId: $sinceId');
    }

    final messages = pages[sinceId] ?? [];
    final hasMore = hasMoreCheck != null
        ? hasMoreCheck!(sinceId ?? 0)
        : (messages.length >= limit);

    final nextSinceId = nextSinceIdOverride != null
        ? nextSinceIdOverride!(sinceId ?? 0)
        : (messages.isNotEmpty ? int.tryParse(messages.last.id) : sinceId);

    return CursorPaginationResponse(
      current: sinceId?.toString(),
      data: messages,
      fromJsonFactory: ChatMessage.fromJson,
      toJsonFactory: (m) => m.toJson(),
      hasMore: hasMore,
      nextSinceId: nextSinceId,
      extra: {
        if (watermarksBySinceId.containsKey(sinceId))
          'watermarks': watermarksBySinceId[sinceId],
      },
    );
  }
}

void main() {
  group('InboxMessageListCursorBloc Delta Sync Tests', () {
    test('Recovers multi-page gap (100 to 1200) across pagination pages', () async {
      // Create pages of 50 items from 101 to 1200
      final pages = <int, List<ChatMessage>>{};
      for (int pageStart = 100; pageStart < 1200; pageStart += 50) {
        final list = <ChatMessage>[];
        for (int id = pageStart + 1; id <= pageStart + 50 && id <= 1200; id++) {
          list.add(ChatMessage(
            id: id.toString(),
            senderId: '2',
            receiverId: '1',
            message: 'Msg $id',
            sentAt: DateTime(2026, 1, 1),
          ));
        }
        pages[pageStart] = list;
      }

      final repo = MockDeltaChatRepository(
        pages: pages,
        hasMoreCheck: (sinceId) => sinceId + 50 < 1200,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: repo,
      );

      // Pre-populate with known message 100
      bloc.upsertLocalItem(ChatMessage(
        id: '100',
        senderId: '2',
        receiverId: '1',
        message: 'Msg 100',
        sentAt: DateTime(2026, 1, 1),
      ));

      expect(bloc.latestMessageId, 100);

      // Run delta sync
      await bloc.syncMissedMessages();

      // Verify all 1100 missed messages + message 100 = 1101 total
      expect(bloc.cursorPageHolder.items.length, 1101);

      // Items must be sorted newest (index 0 = 1200) to oldest (last index = 100)
      expect(bloc.cursorPageHolder.items.first.id, '1200');
      expect(bloc.cursorPageHolder.items.last.id, '100');
      expect(bloc.latestMessageId, 1200);

      // Verify requests were made in sequence
      expect(repo.recordedSinceIds.first, 100);
      expect(repo.recordedSinceIds.last, 1150);
    });

    test('Deduplicates messages arriving via both WebSocket and HTTP sync', () async {
      final msg101 = ChatMessage(
        id: '101',
        senderId: '2',
        receiverId: '1',
        message: 'Msg 101 from HTTP',
        sentAt: DateTime(2026, 1, 1),
      );

      final repo = MockDeltaChatRepository(
        pages: {
          100: [msg101],
        },
        hasMoreCheck: (_) => false,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: repo,
      );

      bloc.upsertLocalItem(ChatMessage(
        id: '100',
        senderId: '2',
        receiverId: '1',
        message: 'Msg 100',
        sentAt: DateTime(2026, 1, 1),
      ));

      // Realtime WebSocket arrives first with Msg 101
      bloc.handleNewMessage(message: ChatMessage(
        id: '101',
        senderId: '2',
        receiverId: '1',
        message: 'Msg 101 from WebSocket',
        sentAt: DateTime(2026, 1, 1),
      ));

      expect(bloc.cursorPageHolder.items.length, 2);

      // HTTP delta sync also brings Msg 101
      await bloc.syncMissedMessages();

      // Must NOT duplicate Msg 101
      expect(bloc.cursorPageHolder.items.length, 2);
      expect(bloc.cursorPageHolder.items.where((m) => m.id == '101').length, 1);
    });

    test('Preserves monotonic watermark (150 is not overwritten by 120)', () async {
      final bloc = InboxMessageListCursorBloc(conversationId: 'conv-1');

      // Set watermark to 150
      bloc.updateMemberWatermark(userId: 2, messageId: 150);
      expect(bloc.userLastMessageSeenID[2], 150);

      // Lower watermark 120 arrives
      bloc.updateMemberWatermark(userId: 2, messageId: 120);
      expect(bloc.userLastMessageSeenID[2], 150); // Preserved!
    });

    test('Updates seen and delivered status when messages list is empty but watermark changed', () async {
      final repo = MockDeltaChatRepository(
        pages: {
          100: [], // 0 new messages
        },
        watermarksBySinceId: {
          100: {
            '100': {
              'users': [
                {'user_id': 2, 'name': 'Bob', 'avatar_url': ''}
              ],
              'count': 1,
            }
          }
        },
        hasMoreCheck: (_) => false,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: repo,
      );

      // Add my message 100, initially unseen
      bloc.upsertLocalItem(ChatMessage(
        id: '100',
        senderId: '1',
        receiverId: '2',
        message: 'My sent message',
        sentAt: DateTime(2026, 1, 1),
        isMine: true,
        isSeen: false,
        isDelivered: false,
      ));

      expect(bloc.cursorPageHolder.items.first.isSeen, false);

      // Run sync: 0 messages, but Bob's watermark is 100
      await bloc.syncMissedMessages();

      // Message 100 must now be marked as seen and delivered!
      expect(bloc.cursorPageHolder.items.first.isSeen, true);
      expect(bloc.cursorPageHolder.items.first.isDelivered, true);
      expect(bloc.userLastMessageSeenID[2], 100);
    });

    test('Guards against simultaneous concurrent sync calls', () async {
      final repo = MockDeltaChatRepository(
        pages: {
          100: [
            ChatMessage(
              id: '101',
              senderId: '2',
              receiverId: '1',
              message: 'Msg 101',
              sentAt: DateTime(2026, 1, 1),
            )
          ],
        },
        hasMoreCheck: (_) => false,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: repo,
      );

      bloc.upsertLocalItem(ChatMessage(
        id: '100',
        senderId: '2',
        receiverId: '1',
        message: 'Msg 100',
        sentAt: DateTime(2026, 1, 1),
      ));

      // Trigger syncMissedMessages twice concurrently
      final future1 = bloc.syncMissedMessages();
      final future2 = bloc.syncMissedMessages();

      await Future.wait([future1, future2]);

      // Only 1 HTTP call made due to _isSyncingMissedMessages guard
      expect(repo.callCount, 1);
    });

    test('Direction 1: WebSocket first (delivered=true, seen=true), HTTP later (delivered=false, seen=false) -> remains true/true', () async {
      final repo = MockDeltaChatRepository(
        pages: {
          140: [
            ChatMessage(
              id: '150',
              senderId: '1',
              receiverId: '2',
              message: 'Hello',
              sentAt: DateTime(2026, 1, 1),
              isMine: true,
              isDelivered: false,
              isSeen: false,
            ),
          ],
        },
        hasMoreCheck: (_) => false,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: repo,
      );

      // 1. Initial message in memory
      bloc.upsertLocalItem(ChatMessage(
        id: '140',
        senderId: '1',
        receiverId: '2',
        message: 'Older message',
        sentAt: DateTime(2026, 1, 1),
        isMine: true,
      ));

      // 2. Realtime WebSocket arrives first: message 150 is delivered=true, seen=true
      bloc.upsertLocalItem(ChatMessage(
        id: '150',
        senderId: '1',
        receiverId: '2',
        message: 'Hello',
        sentAt: DateTime(2026, 1, 1),
        isMine: true,
        isDelivered: true,
        isSeen: true,
      ));

      expect(bloc.cursorPageHolder.items.first.id, '150');
      expect(bloc.cursorPageHolder.items.first.isDelivered, true);
      expect(bloc.cursorPageHolder.items.first.isSeen, true);

      // 3. Stale HTTP delta sync arrives later with delivered=false, seen=false
      await bloc.syncMissedMessages();

      // Expected: Status must NOT be downgraded! Must remain true/true
      final msg150 = bloc.cursorPageHolder.items.firstWhere((m) => m.id == '150');
      expect(msg150.isDelivered, true);
      expect(msg150.isSeen, true);
    });

    test('Direction 2: HTTP first (delivered=false, seen=false), WebSocket later (delivered=true, seen=true) -> upgrades to true/true', () async {
      final repo = MockDeltaChatRepository(
        pages: {
          140: [
            ChatMessage(
              id: '150',
              senderId: '1',
              receiverId: '2',
              message: 'Hello',
              sentAt: DateTime(2026, 1, 1),
              isMine: true,
              isDelivered: false,
              isSeen: false,
            ),
          ],
        },
        hasMoreCheck: (_) => false,
      );

      final bloc = InboxMessageListCursorBloc(
        conversationId: 'conv-1',
        repository: repo,
      );

      // 1. Initial message in memory
      bloc.upsertLocalItem(ChatMessage(
        id: '140',
        senderId: '1',
        receiverId: '2',
        message: 'Older message',
        sentAt: DateTime(2026, 1, 1),
        isMine: true,
      ));

      // 2. HTTP delta sync arrives first with delivered=false, seen=false
      await bloc.syncMissedMessages();

      var msg150 = bloc.cursorPageHolder.items.firstWhere((m) => m.id == '150');
      expect(msg150.isDelivered, false);
      expect(msg150.isSeen, false);

      // 3. WebSocket arrives later with delivered=true, seen=true
      bloc.upsertLocalItem(ChatMessage(
        id: '150',
        senderId: '1',
        receiverId: '2',
        message: 'Hello',
        sentAt: DateTime(2026, 1, 1),
        isMine: true,
        isDelivered: true,
        isSeen: true,
      ));

      // Expected: Status upgrades to true/true
      msg150 = bloc.cursorPageHolder.items.firstWhere((m) => m.id == '150');
      expect(msg150.isDelivered, true);
      expect(msg150.isSeen, true);
    });

    group('readBy merge correctness tests', () {
      const userA = ReadReceiptUser(userId: 1, name: 'User A', avatarUrl: '');
      const userB = ReadReceiptUser(userId: 2, name: 'User B', avatarUrl: '');
      const userC = ReadReceiptUser(userId: 3, name: 'User C', avatarUrl: '');

      test('[A] + [B] -> [A, B]', () {
        final bloc = InboxMessageListCursorBloc(conversationId: 'conv-1');
        final existing = ChatMessage(
          id: '1',
          senderId: '1',
          receiverId: '2',
          message: 'Hi',
          sentAt: DateTime(2026, 1, 1),
          readBy: const [userA],
        );
        final incoming = ChatMessage(
          id: '1',
          senderId: '1',
          receiverId: '2',
          message: 'Hi',
          sentAt: DateTime(2026, 1, 1),
          readBy: const [userB],
        );

        final merged = bloc.mergeItem(existing, incoming);
        expect(merged.readBy.map((u) => u.userId).toList(), [1, 2]);
        expect(merged.readCount, 2);
      });

      test('[A, B] + [B, C] -> [A, B, C]', () {
        final bloc = InboxMessageListCursorBloc(conversationId: 'conv-1');
        final existing = ChatMessage(
          id: '1',
          senderId: '1',
          receiverId: '2',
          message: 'Hi',
          sentAt: DateTime(2026, 1, 1),
          readBy: const [userA, userB],
        );
        final incoming = ChatMessage(
          id: '1',
          senderId: '1',
          receiverId: '2',
          message: 'Hi',
          sentAt: DateTime(2026, 1, 1),
          readBy: const [userB, userC],
        );

        final merged = bloc.mergeItem(existing, incoming);
        expect(merged.readBy.map((u) => u.userId).toList(), [1, 2, 3]);
        expect(merged.readCount, 3);
      });

      test('[A, B] + [A] -> [A, B]', () {
        final bloc = InboxMessageListCursorBloc(conversationId: 'conv-1');
        final existing = ChatMessage(
          id: '1',
          senderId: '1',
          receiverId: '2',
          message: 'Hi',
          sentAt: DateTime(2026, 1, 1),
          readBy: const [userA, userB],
        );
        final incoming = ChatMessage(
          id: '1',
          senderId: '1',
          receiverId: '2',
          message: 'Hi',
          sentAt: DateTime(2026, 1, 1),
          readBy: const [userA],
        );

        final merged = bloc.mergeItem(existing, incoming);
        expect(merged.readBy.map((u) => u.userId).toList(), [1, 2]);
        expect(merged.readCount, 2);
      });

      test('[] + [A] -> [A]', () {
        final bloc = InboxMessageListCursorBloc(conversationId: 'conv-1');
        final existing = ChatMessage(
          id: '1',
          senderId: '1',
          receiverId: '2',
          message: 'Hi',
          sentAt: DateTime(2026, 1, 1),
          readBy: const [],
        );
        final incoming = ChatMessage(
          id: '1',
          senderId: '1',
          receiverId: '2',
          message: 'Hi',
          sentAt: DateTime(2026, 1, 1),
          readBy: const [userA],
        );

        final merged = bloc.mergeItem(existing, incoming);
        expect(merged.readBy.map((u) => u.userId).toList(), [1]);
        expect(merged.readCount, 1);
      });

      test('[A] + [] -> [A]', () {
        final bloc = InboxMessageListCursorBloc(conversationId: 'conv-1');
        final existing = ChatMessage(
          id: '1',
          senderId: '1',
          receiverId: '2',
          message: 'Hi',
          sentAt: DateTime(2026, 1, 1),
          readBy: const [userA],
        );
        final incoming = ChatMessage(
          id: '1',
          senderId: '1',
          receiverId: '2',
          message: 'Hi',
          sentAt: DateTime(2026, 1, 1),
          readBy: const [],
        );

        final merged = bloc.mergeItem(existing, incoming);
        expect(merged.readBy.map((u) => u.userId).toList(), [1]);
        expect(merged.readCount, 1);
      });
    });

    group('syncMissedMessages completion and Seen ACK path tests', () {
      test('full multi-page sync returns true', () async {
        final repo = MockDeltaChatRepository(
          pages: {
            100: [
              ChatMessage(
                id: '101',
                senderId: '2',
                receiverId: '1',
                message: 'Msg 101',
                sentAt: DateTime(2026, 1, 1),
              ),
              ChatMessage(
                id: '150',
                senderId: '2',
                receiverId: '1',
                message: 'Msg 150',
                sentAt: DateTime(2026, 1, 1),
              ),
            ],
            150: [
              ChatMessage(
                id: '180',
                senderId: '2',
                receiverId: '1',
                message: 'Msg 180',
                sentAt: DateTime(2026, 1, 1),
              ),
            ],
          },
          hasMoreCheck: (sinceId) => sinceId == 100, // page 1 hasMore=true, page 2 hasMore=false
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: MockTestChatMessageCache(),
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Msg 100',
          sentAt: DateTime(2026, 1, 1),
        ));

        final success = await bloc.syncMissedMessages();
        expect(success, isTrue);
        expect(bloc.latestMessageId, 180);
        expect(bloc.cursorPageHolder.items.length, 4);
      });

      test('network failure midway returns false and leaves concurrency flag false', () async {
        final repo = MockDeltaChatRepository(
          pages: {
            100: [
              ChatMessage(
                id: '150',
                senderId: '2',
                receiverId: '1',
                message: 'Msg 150',
                sentAt: DateTime(2026, 1, 1),
              ),
            ],
          },
          hasMoreCheck: (sinceId) => sinceId == 100,
          throwOnSinceId: (sinceId) => sinceId == 150, // throws on page 2
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Msg 100',
          sentAt: DateTime(2026, 1, 1),
        ));

        final success = await bloc.syncMissedMessages();
        expect(success, isFalse);
        expect(bloc.isSyncingMissedMessages, isFalse);
      });

      test('invalid/non-advancing cursor (nextSinceId is null when hasMore=true) returns false', () async {
        final repo = MockDeltaChatRepository(
          pages: {
            100: [
              ChatMessage(
                id: '150',
                senderId: '2',
                receiverId: '1',
                message: 'Msg 150',
                sentAt: DateTime(2026, 1, 1),
              ),
            ],
          },
          hasMoreCheck: (_) => true,
          nextSinceIdOverride: (_) => null,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Msg 100',
          sentAt: DateTime(2026, 1, 1),
        ));

        final success = await bloc.syncMissedMessages();
        expect(success, isFalse);
        expect(bloc.isSyncingMissedMessages, isFalse);
      });

      test('invalid/non-advancing cursor (nextSinceId <= currentSinceId when hasMore=true) returns false', () async {
        final repo = MockDeltaChatRepository(
          pages: {
            100: [
              ChatMessage(
                id: '150',
                senderId: '2',
                receiverId: '1',
                message: 'Msg 150',
                sentAt: DateTime(2026, 1, 1),
              ),
            ],
          },
          hasMoreCheck: (_) => true,
          nextSinceIdOverride: (_) => 100,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Msg 100',
          sentAt: DateTime(2026, 1, 1),
        ));

        final success = await bloc.syncMissedMessages();
        expect(success, isFalse);
        expect(bloc.isSyncingMissedMessages, isFalse);
      });

      test('initial load path when latestMessageId is null returns false', () async {
        final repo = MockDeltaChatRepository(pages: {});
        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
        );

        expect(bloc.latestMessageId, isNull);
        final success = await bloc.syncMissedMessages();
        expect(success, isFalse);
      });

      test('successful sync allows Seen ACK path', () async {
        final repo = MockDeltaChatRepository(
          pages: {
            100: [
              ChatMessage(
                id: '105',
                senderId: '2',
                receiverId: '1',
                message: 'Hello',
                sentAt: DateTime(2026, 1, 1),
              ),
            ],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: MockTestChatMessageCache(),
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Msg 100',
          sentAt: DateTime(2026, 1, 1),
        ));

        // Simulating ChatInboxScreen caller logic
        var seenAckCalled = false;
        final success = await bloc.syncMissedMessages();
        if (success == true) {
          seenAckCalled = true;
        }

        expect(seenAckCalled, isTrue);
      });

      test('failed sync blocks Seen ACK path', () async {
        final repo = MockDeltaChatRepository(
          pages: {
            100: [
              ChatMessage(
                id: '105',
                senderId: '2',
                receiverId: '1',
                message: 'Hello',
                sentAt: DateTime(2026, 1, 1),
              ),
            ],
          },
          hasMoreCheck: (_) => true,
          throwOnSinceId: (_) => true,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Msg 100',
          sentAt: DateTime(2026, 1, 1),
        ));

        // Simulating ChatInboxScreen caller logic
        var seenAckCalled = false;
        final success = await bloc.syncMissedMessages();
        if (success == true) {
          seenAckCalled = true;
        }

        expect(seenAckCalled, isFalse);
      });
    });

    group('Delivered ACK after REST delta sync (CHAT-002)', () {
      late MockTestChatSocketService mockSocket;
      late MockTestChatMessageCache mockCache;

      setUp(() {
        mockSocket = MockTestChatSocketService(connected: true);
        mockCache = MockTestChatMessageCache();
        AuthSession.start(
          LoginResponse(
            token: 'test-token',
            refreshToken: 'test-refresh',
            user: User(id: 1, name: 'Current User'),
          ),
        );
      });

      tearDown(() {
        AuthSession.clear();
      });

      test('dispatches sendDeliveredAck for un-delivered messages from other senders after durable persistence', () async {
        final incomingMsg = ChatMessage(
          id: '105',
          senderId: '2',
          receiverId: '1',
          message: 'Hello from User 2',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: false,
          isSeen: false,
          isMine: false,
        );

        final repo = MockDeltaChatRepository(
          pages: {
            100: [incomingMsg],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: mockCache,
          socketService: mockSocket,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Previous msg',
          sentAt: DateTime(2026, 1, 1),
        ));

        final success = await bloc.syncMissedMessages();
        expect(success, isTrue);

        // 1. Persistence happened first
        expect(mockCache.saveCalled, isTrue);
        expect(mockCache.savedMessages?.any((m) => m.id == '105'), isTrue);

        // 2. Delivery ACK was dispatched with exact backend schema
        expect(mockSocket.dispatchedDeliveredAcks.length, equals(1));
        final ack = mockSocket.dispatchedDeliveredAcks.first;
        expect(ack['conversation_id'], equals('conv-1'));
        expect(ack['message_id'], equals('105'));
        expect(ack['sender_id'], equals(2));

        // 3. Tracked as delivered-acked and pending is cleared
        expect(bloc.deliveredAckedMessageIds.contains('105'), isTrue);
        expect(bloc.pendingDeliveredAcks, isEmpty);

        await bloc.close();
      });

      test('NEVER ACKs messages sent by the current user (isMine=true or senderId=myId)', () async {
        final myMsgBySenderId = ChatMessage(
          id: '105',
          senderId: '1', // Matches logged in user id 1
          receiverId: 'conv-1',
          message: 'Message from myself',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: false,
          isSeen: false,
          isMine: false,
        );
        final myMsgByFlag = ChatMessage(
          id: '106',
          senderId: '99',
          receiverId: 'conv-1',
          message: 'Message with isMine flag',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: false,
          isSeen: false,
          isMine: true,
        );

        final repo = MockDeltaChatRepository(
          pages: {
            100: [myMsgBySenderId, myMsgByFlag],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: mockCache,
          socketService: mockSocket,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '1',
          receiverId: 'conv-1',
          message: 'Previous msg',
          sentAt: DateTime(2026, 1, 1),
        ));

        final success = await bloc.syncMissedMessages();
        expect(success, isTrue);

        // Delivery ACK must NEVER be dispatched for own messages
        expect(mockSocket.dispatchedDeliveredAcks, isEmpty);
        expect(bloc.deliveredAckedMessageIds, isEmpty);
        expect(bloc.pendingDeliveredAcks, isEmpty);

        await bloc.close();
      });

      test('NEVER ACKs messages already marked isDelivered=true or isSeen=true', () async {
        final deliveredMsg = ChatMessage(
          id: '105',
          senderId: '2',
          receiverId: '1',
          message: 'Already delivered',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: true,
          isSeen: false,
        );
        final seenMsg = ChatMessage(
          id: '106',
          senderId: '2',
          receiverId: '1',
          message: 'Already seen',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: false,
          isSeen: true,
        );

        final repo = MockDeltaChatRepository(
          pages: {
            100: [deliveredMsg, seenMsg],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: mockCache,
          socketService: mockSocket,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Previous msg',
          sentAt: DateTime(2026, 1, 1),
        ));

        final success = await bloc.syncMissedMessages();
        expect(success, isTrue);

        // Already delivered or seen messages must NOT be re-ACKed
        expect(mockSocket.dispatchedDeliveredAcks, isEmpty);
        expect(bloc.deliveredAckedMessageIds, isEmpty);

        await bloc.close();
      });

      test('is strictly idempotent across repeated delta-sync responses (no duplicate ACKs)', () async {
        final incomingMsg = ChatMessage(
          id: '105',
          senderId: '2',
          receiverId: '1',
          message: 'Hello',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: false,
          isSeen: false,
        );

        final repo = MockDeltaChatRepository(
          pages: {
            100: [incomingMsg],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: mockCache,
          socketService: mockSocket,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Previous msg',
          sentAt: DateTime(2026, 1, 1),
        ));

        // First sync
        await bloc.syncMissedMessages();
        expect(mockSocket.dispatchedDeliveredAcks.length, equals(1));

        // Second sync with identical response
        await bloc.syncMissedMessages();
        // Dispatched count must remain 1 - no duplicate delivery ACK
        expect(mockSocket.dispatchedDeliveredAcks.length, equals(1));

        await bloc.close();
      });

      test('persistence failure blocks delivery ACKs from being dispatched', () async {
        final failingCache = FailingChatMessageCache();
        final incomingMsg = ChatMessage(
          id: '105',
          senderId: '2',
          receiverId: '1',
          message: 'Hello',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: false,
          isSeen: false,
        );

        final repo = MockDeltaChatRepository(
          pages: {
            100: [incomingMsg],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: failingCache,
          socketService: mockSocket,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Previous msg',
          sentAt: DateTime(2026, 1, 1),
        ));

        // Sync must fail due to cache storage failure
        final success = await bloc.syncMissedMessages();
        expect(success, isFalse);

        // Crucial invariant: NO delivery ACK is sent when persistence fails
        expect(mockSocket.dispatchedDeliveredAcks, isEmpty);
        expect(bloc.deliveredAckedMessageIds, isEmpty);
        expect(bloc.pendingDeliveredAcks, isEmpty);

        await bloc.close();
      });

      test('disconnected socket retains pending ACKs and flushes when socket reconnects', () async {
        final offlineSocket = MockTestChatSocketService(connected: false);
        final incomingMsg = ChatMessage(
          id: '105',
          senderId: '2',
          receiverId: '1',
          message: 'Hello offline',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: false,
          isSeen: false,
        );

        final repo = MockDeltaChatRepository(
          pages: {
            100: [incomingMsg],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: mockCache,
          socketService: offlineSocket,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Previous msg',
          sentAt: DateTime(2026, 1, 1),
        ));

        // Sync succeeds because messages are persisted locally
        final success = await bloc.syncMissedMessages();
        expect(success, isTrue);

        // Socket is disconnected, so ACK could not be sent yet
        expect(offlineSocket.dispatchedDeliveredAcks, isEmpty);
        expect(bloc.pendingDeliveredAcks.containsKey('105'), isTrue);
        expect(bloc.pendingDeliveredAcks['105'], equals(2));
        expect(bloc.deliveredAckedMessageIds, isEmpty);

        // Socket reconnects!
        offlineSocket.setConnected(true);

        // Listener triggers automatic flush of pending ACKs
        expect(offlineSocket.dispatchedDeliveredAcks.length, equals(1));
        expect(offlineSocket.dispatchedDeliveredAcks.first['message_id'], equals('105'));
        expect(bloc.pendingDeliveredAcks, isEmpty);
        expect(bloc.deliveredAckedMessageIds.contains('105'), isTrue);

        await bloc.close();
      });

      test('multi-page delta sync collects and ACKs all un-delivered messages across pages', () async {
        final page1Msg1 = ChatMessage(id: '101', senderId: '2', receiverId: '1', message: 'M1', sentAt: DateTime(2026, 1, 1));
        final page1Msg2 = ChatMessage(id: '102', senderId: '3', receiverId: '1', message: 'M2', sentAt: DateTime(2026, 1, 1));
        final page2Msg1 = ChatMessage(id: '103', senderId: '2', receiverId: '1', message: 'M3', sentAt: DateTime(2026, 1, 1));
        final page2Msg2 = ChatMessage(id: '104', senderId: '4', receiverId: '1', message: 'M4', sentAt: DateTime(2026, 1, 1));

        final repo = MockDeltaChatRepository(
          pages: {
            100: [page1Msg1, page1Msg2],
            102: [page2Msg1, page2Msg2],
          },
          hasMoreCheck: (sinceId) => sinceId == 100,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: mockCache,
          socketService: mockSocket,
        );

        bloc.upsertLocalItem(ChatMessage(id: '100', senderId: '2', receiverId: '1', message: 'M0', sentAt: DateTime(2026, 1, 1)));

        final success = await bloc.syncMissedMessages();
        expect(success, isTrue);

        expect(mockSocket.dispatchedDeliveredAcks.length, equals(4));
        final ackedIds = mockSocket.dispatchedDeliveredAcks.map((a) => a['message_id']).toSet();
        expect(ackedIds, equals({'101', '102', '103', '104'}));
        expect(bloc.deliveredAckedMessageIds, equals({'101', '102', '103', '104'}));

        await bloc.close();
      });

      test('clearLocalItems resets both pending and delivered ACK tracking', () async {
        final incomingMsg = ChatMessage(
          id: '105',
          senderId: '2',
          receiverId: '1',
          message: 'Hello',
          sentAt: DateTime(2026, 1, 1),
        );

        final repo = MockDeltaChatRepository(
          pages: {
            100: [incomingMsg],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: mockCache,
          socketService: mockSocket,
        );

        bloc.upsertLocalItem(ChatMessage(id: '100', senderId: '2', receiverId: '1', message: 'M0', sentAt: DateTime(2026, 1, 1)));

        await bloc.syncMissedMessages();
        expect(bloc.deliveredAckedMessageIds.contains('105'), isTrue);

        bloc.clearLocalItems();
        expect(bloc.deliveredAckedMessageIds, isEmpty);
        expect(bloc.pendingDeliveredAcks, isEmpty);

        await bloc.close();
      });

      test('silent abort in saveMessages (returns false) prevents delivery ACK staging and dispatch', () async {
        final silentAbortCache = SilentAbortChatMessageCache();
        final incomingMsg = ChatMessage(
          id: '105',
          senderId: '2',
          receiverId: '1',
          message: 'Hello silent abort',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: false,
          isSeen: false,
        );

        final repo = MockDeltaChatRepository(
          pages: {
            100: [incomingMsg],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: silentAbortCache,
          socketService: mockSocket,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Previous msg',
          sentAt: DateTime(2026, 1, 1),
        ));

        final success = await bloc.syncMissedMessages();
        expect(success, isFalse);

        // Verification: No ACKs are staged or dispatched when persistence silently aborts
        expect(mockSocket.dispatchedDeliveredAcks, isEmpty);
        expect(bloc.deliveredAckedMessageIds, isEmpty);
        expect(bloc.pendingDeliveredAcks, isEmpty);

        await bloc.close();
      });

      test('sendDeliveredAck failure retains message in pendingDeliveredAcks and retries on flush/reconnect without duplicates', () async {
        final failingSocket = MockTestChatSocketService(connected: true);
        failingSocket.shouldFailSend = true;

        final incomingMsg = ChatMessage(
          id: '105',
          senderId: '2',
          receiverId: '1',
          message: 'Hello retry',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: false,
          isSeen: false,
        );

        final repo = MockDeltaChatRepository(
          pages: {
            100: [incomingMsg],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-1',
          repository: repo,
          messageCache: mockCache,
          socketService: failingSocket,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '100',
          senderId: '2',
          receiverId: '1',
          message: 'Previous msg',
          sentAt: DateTime(2026, 1, 1),
        ));

        // Sync runs, persistence succeeds, but socket dispatch fails
        final success = await bloc.syncMissedMessages();
        expect(success, isTrue);

        // ACK was NOT sent and NOT marked as acked
        expect(failingSocket.dispatchedDeliveredAcks, isEmpty);
        expect(bloc.deliveredAckedMessageIds, isEmpty);
        expect(bloc.pendingDeliveredAcks.containsKey('105'), isTrue);
        expect(bloc.pendingDeliveredAcks['105'], equals(2));

        // Network recovers: sending now succeeds
        failingSocket.shouldFailSend = false;
        bloc.flushPendingDeliveredAcks();

        expect(failingSocket.dispatchedDeliveredAcks.length, equals(1));
        expect(failingSocket.dispatchedDeliveredAcks.first['message_id'], equals('105'));
        expect(failingSocket.dispatchedDeliveredAcks.first['sender_id'], equals(2));
        expect(bloc.pendingDeliveredAcks, isEmpty);
        expect(bloc.deliveredAckedMessageIds.contains('105'), isTrue);

        // Second flush does not re-dispatch (idempotent / no duplicate)
        bloc.flushPendingDeliveredAcks();
        expect(failingSocket.dispatchedDeliveredAcks.length, equals(1));

        await bloc.close();
      });

      test('account switch and session epoch drift purge pending ACKs preventing cross-account leakage', () async {
        final initialResolver = ChatMessageCache.userScopeResolver;
        try {
          ChatMessageCache.userScopeResolver = () => 'user-101';

          final offlineSocket = MockTestChatSocketService(connected: false);
          final testCache = MockTestChatMessageCache();

          final incomingMsg = ChatMessage(
            id: '105',
            senderId: '2',
            receiverId: 'user-101',
            message: 'Secret message for user 101',
            sentAt: DateTime(2026, 1, 1),
            isDelivered: false,
            isSeen: false,
          );

          final repo = MockDeltaChatRepository(
            pages: {
              100: [incomingMsg],
            },
            hasMoreCheck: (_) => false,
          );

          final bloc = InboxMessageListCursorBloc(
            conversationId: 'conv-1',
            repository: repo,
            messageCache: testCache,
            socketService: offlineSocket,
          );

          bloc.upsertLocalItem(ChatMessage(
            id: '100',
            senderId: '2',
            receiverId: 'user-101',
            message: 'Previous msg',
            sentAt: DateTime(2026, 1, 1),
          ));

          // User 101 syncs while socket is disconnected
          final syncResult = await bloc.syncMissedMessages();
          expect(syncResult, isTrue);
          expect(bloc.pendingDeliveredAcks.containsKey('105'), isTrue);
          expect(offlineSocket.dispatchedDeliveredAcks, isEmpty);

          // User 101 logs out: session epoch is incremented and user scope switches to User 102
          testCache.incrementSessionEpochForTesting();
          ChatMessageCache.userScopeResolver = () => 'user-102';

          // User 102 connects socket
          offlineSocket.setConnected(true);

          // Verify pending ACKs from User 101 were invalidated and NOT sent over User 102's socket
          expect(offlineSocket.dispatchedDeliveredAcks, isEmpty);
          expect(bloc.pendingDeliveredAcks, isEmpty);
          expect(bloc.deliveredAckedMessageIds, isEmpty);

          await bloc.close();
        } finally {
          ChatMessageCache.userScopeResolver = initialResolver;
        }
      });

      test('delivery ACK payload strictly conforms to Go backend AckPayload schema', () async {
        final incomingMsg = ChatMessage(
          id: '54321',
          senderId: '987',
          receiverId: '1',
          message: 'Contract check message',
          sentAt: DateTime(2026, 1, 1),
          isDelivered: false,
          isSeen: false,
        );

        final repo = MockDeltaChatRepository(
          pages: {
            54300: [incomingMsg],
          },
          hasMoreCheck: (_) => false,
        );

        final bloc = InboxMessageListCursorBloc(
          conversationId: 'conv-contract-test',
          repository: repo,
          messageCache: mockCache,
          socketService: mockSocket,
        );

        bloc.upsertLocalItem(ChatMessage(
          id: '54300',
          senderId: '987',
          receiverId: '1',
          message: 'Previous msg',
          sentAt: DateTime(2026, 1, 1),
        ));

        await bloc.syncMissedMessages();

        expect(mockSocket.dispatchedDeliveredAcks.length, equals(1));
        final ack = mockSocket.dispatchedDeliveredAcks.first;

        // Verify Go backend hub.go / event.go expectations:
        // AckPayload: MessageID (int64/int), ConversationID (string), SenderID (int)
        expect(ack['conversation_id'], isA<String>());
        expect(ack['conversation_id'], equals('conv-contract-test'));
        expect(ack['message_id'], equals('54321'));
        expect(ack['sender_id'], isA<int>());
        expect(ack['sender_id'], equals(987));

        await bloc.close();
      });
    });
  });
}
