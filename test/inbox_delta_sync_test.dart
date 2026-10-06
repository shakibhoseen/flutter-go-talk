import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/home/data/http_chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';

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
  });
}
