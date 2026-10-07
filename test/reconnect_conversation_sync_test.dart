import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_outbox_processor.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_sync_coordinator.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/local_outbox_storage.dart';
import 'package:whatsapp_flutter_go/feature/home/data/chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_user.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/view_model/chat_view_model.dart';

class MockConversationRepository implements ChatRepository {
  List<Conversation> conversationsToReturn;
  Completer<List<Conversation>>? delayCompleter;
  int getConversationsCallCount = 0;

  MockConversationRepository({
    this.conversationsToReturn = const [],
    this.delayCompleter,
  });

  @override
  Future<List<Conversation>> getConversations() async {
    getConversationsCallCount++;
    if (delayCompleter != null) {
      return delayCompleter!.future;
    }
    return conversationsToReturn;
  }

  @override
  Future<List<ChatUser>> getAllUsers() async => const [];

  @override
  Future<String> getOrCreateDirectConversation(int targetUserId) async => 'conv-1';

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  }) async {
    return CursorPaginationResponse(
      data: const [],
      fromJsonFactory: ChatMessage.fromJson,
      toJsonFactory: (m) => m.toJson(),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Reconnect Conversation Sync Tests', () {
    test('Test 1 — Reconnect triggers conversation refresh and updates last message preview', () async {
      final initialConv = Conversation(
        id: 'conv-1',
        type: 'direct',
        title: 'Alice',
        lastMessageId: 10,
        lastMessageContent: 'Old message',
        lastMessageAt: DateTime.utc(2026, 10, 7, 10, 0),
        createdAt: DateTime.utc(2026, 10, 7, 9, 0),
      );

      final repo = MockConversationRepository(
        conversationsToReturn: [initialConv],
      );

      final outbox = InMemoryOutboxStorage();
      final coordinator = ChatSyncCoordinator(
        outboxStorage: outbox,
        outboxProcessor: ChatOutboxProcessor(outboxStorage: outbox),
      );

      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: coordinator,
      );

      // Wait for initial load
      await pumpEventQueue();
      expect(viewModel.conversationsBloc.state, isA<SuccessState<List<Conversation>>>());
      final state1 = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(state1.data.first.lastMessageId, equals(10));
      expect(state1.data.first.lastMessageContent, equals('Old message'));
      expect(repo.getConversationsCallCount, equals(1));

      // Server now has updated missed message from User A
      final updatedConv = Conversation(
        id: 'conv-1',
        type: 'direct',
        title: 'Alice',
        lastMessageId: 20,
        lastMessageContent: 'Missed message from A',
        lastMessageAt: DateTime.utc(2026, 10, 7, 11, 0),
        createdAt: DateTime.utc(2026, 10, 7, 9, 0),
      );
      repo.conversationsToReturn = [updatedConv];

      // Reconnect occurs
      await coordinator.handleReconnect();
      await pumpEventQueue();

      expect(repo.getConversationsCallCount, equals(2));
      final state2 = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(state2.data.first.lastMessageId, equals(20));
      expect(state2.data.first.lastMessageContent, equals('Missed message from A'));
      expect(state2.data.first.lastMessageAt, equals(DateTime.utc(2026, 10, 7, 11, 0)));

      viewModel.dispose();
    });

    test('Test 2 — Refresh does not cause duplicate request while initial conversations load is active', () async {
      final completer = Completer<List<Conversation>>();
      final repo = MockConversationRepository(
        delayCompleter: completer,
      );

      final outbox = InMemoryOutboxStorage();
      final coordinator = ChatSyncCoordinator(
        outboxStorage: outbox,
        outboxProcessor: ChatOutboxProcessor(outboxStorage: outbox),
      );

      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: coordinator,
      );

      // Initial load was kicked off in constructor and is waiting for completer
      await Future.microtask(() {});
      expect(viewModel.conversationsBloc.isLoading, isTrue);
      expect(repo.getConversationsCallCount, equals(1));

      // Socket connects and triggers reconnect while initial load is still in flight
      await coordinator.handleReconnect();

      // Must NOT fire a duplicate GET /conversations request
      expect(repo.getConversationsCallCount, equals(1));

      // Now complete initial load
      completer.complete([
        Conversation(
          id: 'conv-1',
          type: 'direct',
          lastMessageId: 5,
          lastMessageContent: 'Initial',
          createdAt: DateTime.utc(2026, 10, 7, 9, 0),
        ),
      ]);
      await pumpEventQueue();

      expect(viewModel.conversationsBloc.isLoading, isFalse);
      expect(viewModel.conversationsBloc.state, isA<SuccessState<List<Conversation>>>());

      // Subsequent refresh now succeeds
      repo.delayCompleter = null;
      repo.conversationsToReturn = [
        Conversation(
          id: 'conv-1',
          type: 'direct',
          lastMessageId: 6,
          lastMessageContent: 'Updated after connect',
          createdAt: DateTime.utc(2026, 10, 7, 9, 0),
        ),
      ];

      await coordinator.handleReconnect();
      await pumpEventQueue();

      expect(repo.getConversationsCallCount, equals(2));
      final state = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(state.data.first.lastMessageContent, equals('Updated after connect'));

      viewModel.dispose();
    });

    test('Test 3 — Live newer conversation data is not downgraded by an older refresh response', () async {
      final completer = Completer<List<Conversation>>();
      final initialConv = Conversation(
        id: 'conv-1',
        type: 'direct',
        title: 'Alice',
        lastMessageId: 100,
        lastMessageContent: 'Snapshot message 100',
        lastMessageAt: DateTime.utc(2026, 10, 7, 10, 0),
        createdAt: DateTime.utc(2026, 10, 7, 9, 0),
      );

      final repo = MockConversationRepository(
        conversationsToReturn: [initialConv],
      );

      final outbox = InMemoryOutboxStorage();
      final coordinator = ChatSyncCoordinator(
        outboxStorage: outbox,
        outboxProcessor: ChatOutboxProcessor(outboxStorage: outbox),
      );

      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: coordinator,
      );

      await pumpEventQueue();
      expect(viewModel.conversationsBloc.state, isA<SuccessState<List<Conversation>>>());

      // Next GET /conversations will be delayed and return older snapshot (msg 100)
      repo.delayCompleter = completer;

      // Start refresh (GET /conversations in flight)
      final refreshFuture = viewModel.refreshConversations();

      // In the meantime, a live WebSocket EventNewMessage lands with message ID 105
      viewModel.handleNewMessageForTest({
        'id': 105,
        'conversation_id': 'conv-1',
        'content': 'Live new message 105',
        'sender_id': 2,
        'created_at': DateTime.utc(2026, 10, 7, 10, 5).toIso8601String(),
      });

      // Verify in-memory head is updated to live message 105
      var currentState = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(currentState.data.first.lastMessageId, equals(105));
      expect(currentState.data.first.lastMessageContent, equals('Live new message 105'));

      // Now the delayed GET /conversations finishes with the older snapshot (message 100)
      completer.complete([initialConv]);
      await refreshFuture;
      await pumpEventQueue();

      // Monotonic guard: in-memory head must NOT be downgraded back to 100!
      currentState = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(currentState.data.first.lastMessageId, equals(105));
      expect(currentState.data.first.lastMessageContent, equals('Live new message 105'));

      viewModel.dispose();
    });

    test('Test 4 — Callback is unregistered on dispose', () async {
      final repo = MockConversationRepository(
        conversationsToReturn: const [],
      );

      final outbox = InMemoryOutboxStorage();
      final coordinator = ChatSyncCoordinator(
        outboxStorage: outbox,
        outboxProcessor: ChatOutboxProcessor(outboxStorage: outbox),
      );

      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: coordinator,
      );

      await pumpEventQueue();
      expect(repo.getConversationsCallCount, equals(1));

      // Dispose viewModel
      viewModel.dispose();

      // Trigger reconnect
      await coordinator.handleReconnect();
      await pumpEventQueue();

      // getConversations must NOT be called after dispose
      expect(repo.getConversationsCallCount, equals(1));
    });
  });
}
