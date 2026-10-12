import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:whatsapp_flutter_go/core/db/local_cache/cache_manager.dart';
import 'package:whatsapp_flutter_go/core/db/local_cache/hive_initializer.dart';
import 'package:whatsapp_flutter_go/core/db/network/chat_endpoints.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_sync_coordinator.dart';
import 'package:whatsapp_flutter_go/feature/home/data/http_chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/view_model/chat_view_model.dart';
import 'package:whatsapp_flutter_go/feature/login/model/login_response.dart';

/// Testable HttpChatRepository where the network fetch can be controlled.
class TestableHttpChatRepository extends HttpChatRepository {
  TestableHttpChatRepository({this.fetchHandler});

  Future<dynamic> Function(String endpoint, Map<String, dynamic>? query)?
      fetchHandler;

  @override
  Future<dynamic> fetch(String endpoint, Map<String, dynamic>? query) {
    if (fetchHandler != null) {
      return fetchHandler!(endpoint, query);
    }
    return super.fetch(endpoint, query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('conv_cache_test_');
    HiveInitializer.resetForTesting();
    CacheManager().resetForTesting();
    HttpChatRepository.resetWriteSequencingForTesting();
    CacheManager.cacheScopeResolver = () => 'test_scope';
    CacheManager.userScopeResolver =
        () => AuthSession.tokens?.user?.id?.toString() ?? 'guest';
    await HiveInitializer.ensureInitialized(tempDir.path);
  });

  tearDown(() async {
    AuthSession.clear();
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    HiveInitializer.resetForTesting();
    CacheManager().resetForTesting();
    HttpChatRepository.resetWriteSequencingForTesting();
  });

  Conversation createTestConversation({
    required String id,
    required String title,
    String? content,
    int? messageId,
    DateTime? lastAt,
  }) {
    final now = lastAt ?? DateTime.now();
    return Conversation(
      id: id,
      type: 'direct',
      title: title,
      lastMessageId: messageId,
      lastMessageContent: content ?? 'Hello $title',
      lastMessageAt: now,
      createdAt: now,
    );
  }

  group('Phase 1: Persistent Cache-First Conversation List', () {
    test('1. Cached conversations render when offline', () async {
      final repo = TestableHttpChatRepository();

      final now = DateTime.now();
      final c1 = createTestConversation(
        id: 'c1',
        title: 'Alice',
        lastAt: now.add(const Duration(minutes: 5)),
      );
      final c2 = createTestConversation(
        id: 'c2',
        title: 'Bob',
        lastAt: now,
      );

      // Seed cache
      await repo.persistConversations([c1, c2]);

      // Network is offline
      repo.fetchHandler = (endpoint, query) async {
        throw DioException(
          requestOptions: RequestOptions(path: endpoint),
          type: DioExceptionType.connectionError,
          error: 'Offline',
        );
      };

      // Watch conversations stream directly
      final emitted = await repo.watchConversations().toList();
      expect(emitted.length, equals(1));
      expect(emitted.first.length, equals(2));
      expect(emitted.first[0].id, equals('c1'));
      expect(emitted.first[1].id, equals('c2'));

      // Also verify through ChatViewModel and Bloc
      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: ChatSyncCoordinator.instance,
      );

      // Wait for stream to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(viewModel.conversationsBloc.state, isA<SuccessState<List<Conversation>>>());
      final state = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(state.data.length, equals(2));
      expect(state.data[0].title, equals('Alice'));
      expect(state.data[1].title, equals('Bob'));

      viewModel.dispose();
    });

    test('2. Cached conversations appear before fresh network data', () async {
      final repo = TestableHttpChatRepository();

      final cOld = createTestConversation(
        id: 'c1',
        title: 'Old Title',
        content: 'Old Content',
      );
      final cFresh = createTestConversation(
        id: 'c1',
        title: 'Fresh Title',
        content: 'Fresh Content',
      );

      // Seed cache with stale data
      await repo.persistConversations([cOld]);

      // Network returns fresh data after an intentional delay
      final networkCompleter = Completer<Map<String, dynamic>>();
      repo.fetchHandler = (endpoint, query) => networkCompleter.future;

      final emissions = <List<Conversation>>[];
      final sub = repo.watchConversations().listen(emissions.add);

      // Allow microtasks for cached read to emit
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(emissions.length, equals(1),
          reason: 'Cached copy must emit immediately before network responds');
      expect(emissions.first.first.title, equals('Old Title'));

      // Network completes
      networkCompleter.complete({
        'conversations': [cFresh.toJson()],
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(emissions.length, equals(2),
          reason: 'Fresh network copy must emit as the second emission');
      expect(emissions.last.first.title, equals('Fresh Title'));

      await sub.cancel();
    });

    test('3. Fresh network data replaces/updates stale cached data', () async {
      final repo = TestableHttpChatRepository();

      final cOld = createTestConversation(id: 'c1', title: 'Stale Alice');
      final cUpdated = createTestConversation(id: 'c1', title: 'Updated Alice');

      // Seed cache with stale
      await repo.persistConversations([cOld]);

      // Network returns updated
      repo.fetchHandler = (endpoint, query) async {
        return {
          'conversations': [cUpdated.toJson()],
        };
      };

      // Run watchConversations to completion
      final emissions = await repo.watchConversations().toList();
      expect(emissions.length, equals(2));
      expect(emissions.last.first.title, equals('Updated Alice'));

      // Now verify persistent cache was actually updated in Hive
      final cachedRaw = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
        allowExpired: true,
      );
      expect(cachedRaw, isNotNull);
      final list = cachedRaw!['conversations'] as List;
      expect(list.first['title'], equals('Updated Alice'));
    });

    test('4. No-cache plus network failure follows the existing error behavior', () async {
      final repo = TestableHttpChatRepository();

      // Ensure no cache exists
      await repo.cache.clearAllCache();

      // Network fails
      repo.fetchHandler = (endpoint, query) async {
        throw DioException(
          requestOptions: RequestOptions(path: endpoint),
          type: DioExceptionType.connectionError,
          error: 'Connection refused',
        );
      };

      // Direct stream must rethrow when no cache is served
      expect(
        () => repo.watchConversations().toList(),
        throwsA(isA<DioException>()),
      );

      // In ChatViewModel, conversationsBloc must enter ErrorState
      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: ChatSyncCoordinator.instance,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(viewModel.conversationsBloc.state, isA<ErrorState>());

      viewModel.dispose();
    });

    test('5. User A\'s cached list is never shown to User B', () async {
      final repo = TestableHttpChatRepository();

      // Log in User A
      AuthSession.adopt(
        LoginResponse(
          token: 'token_user_a',
          user: User(id: 101, name: 'User A'),
        ),
      );

      final cUserA = createTestConversation(id: 'cA', title: 'Secret A Chat');
      await repo.persistConversations([cUserA]);

      // Verify User A reads User A's cached conversation
      final userAStream = await repo.watchConversations().first;
      expect(userAStream.length, equals(1));
      expect(userAStream.first.title, equals('Secret A Chat'));

      // User A logs out
      AuthSession.clear();

      // Log in User B
      AuthSession.adopt(
        LoginResponse(
          token: 'token_user_b',
          user: User(id: 202, name: 'User B'),
        ),
      );

      // Network is offline for User B
      repo.fetchHandler = (endpoint, query) async {
        throw DioException(
          requestOptions: RequestOptions(path: endpoint),
          type: DioExceptionType.connectionError,
          error: 'Offline',
        );
      };

      // User B must NOT see User A's conversations
      final userBViewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: ChatSyncCoordinator.instance,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // User B has no cache, so network failure must enter ErrorState and NOT show User A's data
      expect(userBViewModel.conversationsBloc.state, isA<ErrorState>());
      expect(userBViewModel.conversationsBloc.state is SuccessState, isFalse);

      userBViewModel.dispose();
    });

    test('6. WebSocket mutations persist to cache immediately', () async {
      final repo = TestableHttpChatRepository();

      // Seed cache
      final cInitial = createTestConversation(
        id: 'c1',
        title: 'Initial Title',
        content: 'Initial Message',
      );
      await repo.persistConversations([cInitial]);

      repo.fetchHandler = (endpoint, query) async {
        return {
          'conversations': [cInitial.toJson()],
        };
      };

      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: ChatSyncCoordinator.instance,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Simulate incoming WebSocket message on existing conversation
      viewModel.handleSocketEventForTesting({
        'type': 'new_message',
        'payload': {
          'conversation_id': 'c1',
          'id': 999,
          'content': 'Live Socket Message',
          'sender_id': 555,
          'sender_name': 'Sender',
          'created_at': DateTime.now().toIso8601String(),
        },
      });

      // Allow async persist to write
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Verify persistent cache now has the live message
      final cachedRaw = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
      );
      expect(cachedRaw, isNotNull);
      final list = cachedRaw!['conversations'] as List;
      expect(list.first['last_message_content'], equals('Live Socket Message'));
      expect(list.first['last_message_id'], equals(999));

      viewModel.dispose();
    });

    test('7. P0: Delayed User A cache write never pollutes User B or guest cache upon switch', () async {
      final repo = TestableHttpChatRepository();

      // Log in User A
      AuthSession.adopt(
        LoginResponse(
          token: 'token_user_a',
          user: User(id: 101, name: 'User A'),
        ),
      );

      final delayedFetchCompleter = Completer<Map<String, dynamic>>();
      repo.fetchHandler = (endpoint, query) => delayedFetchCompleter.future;

      final cUserA = createTestConversation(id: 'cA', title: 'User A Secret');

      // User A initiates a network fetch (e.g. getConversations)
      final fetchFuture = repo.getConversations();

      // While the request is in flight, User A logs out!
      AuthSession.clear();

      // Log in User B
      AuthSession.adopt(
        LoginResponse(
          token: 'token_user_b',
          user: User(id: 202, name: 'User B'),
        ),
      );

      // User A's slow network request now completes
      delayedFetchCompleter.complete({
        'conversations': [cUserA.toJson()],
      });
      await fetchFuture;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // User B must NOT see User A's data in User B's cache
      final userBCache = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
        allowExpired: true,
      );
      expect(userBCache, isNull, reason: 'Delayed User A write must not write into User B cache');

      // Also verify guest cache is not polluted
      final guestCache = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
        allowExpired: true,
        targetUserScope: 'guest',
      );
      expect(guestCache, isNull, reason: 'Delayed User A write must not write into guest cache');
    });

    test('8. P1: Server list shrinking removes missing confirmed conversations', () async {
      final repo = TestableHttpChatRepository();

      final now = DateTime.now();
      final c1 = createTestConversation(
        id: 'c1',
        title: 'Conv 1',
        messageId: 10,
        lastAt: now.add(const Duration(minutes: 10)),
      );
      final c2 = createTestConversation(
        id: 'c2',
        title: 'Conv 2',
        messageId: 20,
        lastAt: now.add(const Duration(minutes: 5)),
      );
      final c3 = createTestConversation(
        id: 'c3',
        title: 'Conv 3',
        messageId: 30,
        lastAt: now,
      );

      // Seed cache with all 3 conversations
      await repo.persistConversations([c1, c2, c3]);

      final networkCompleter = Completer<Map<String, dynamic>>();
      repo.fetchHandler = (endpoint, query) => networkCompleter.future;

      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: ChatSyncCoordinator.instance,
      );

      // Allow initial cache load
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect((viewModel.conversationsBloc.state as SuccessState<List<Conversation>>).data.length, equals(3));

      // Server returns only c1 and c2 (c3 was deleted/left)
      networkCompleter.complete({
        'conversations': [c1.toJson(), c2.toJson()],
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(state.data.length, equals(2));
      expect(state.data.map((c) => c.id).toList(), equals(['c1', 'c2']));

      // Verify persistent cache in Hive was also updated
      final cachedRaw = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
      );
      final list = cachedRaw!['conversations'] as List;
      expect(list.length, equals(2));
      expect(list.map((c) => c['id']).toList(), equals(['c1', 'c2']));

      viewModel.dispose();
    });

    test('9. P1: Empty server list clears all confirmed conversations', () async {
      final repo = TestableHttpChatRepository();

      final c1 = createTestConversation(id: 'c1', title: 'Conv 1', messageId: 10);
      final c2 = createTestConversation(id: 'c2', title: 'Conv 2', messageId: 20);

      // Seed cache
      await repo.persistConversations([c1, c2]);

      final networkCompleter = Completer<Map<String, dynamic>>();
      repo.fetchHandler = (endpoint, query) => networkCompleter.future;

      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: ChatSyncCoordinator.instance,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect((viewModel.conversationsBloc.state as SuccessState<List<Conversation>>).data.length, equals(2));

      // Server returns empty list
      networkCompleter.complete({
        'conversations': [],
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(state.data.isEmpty, isTrue);

      final cachedRaw = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
      );
      final list = cachedRaw!['conversations'] as List;
      expect(list.isEmpty, isTrue);

      viewModel.dispose();
    });

    test('10. P1: Optimistically created unconfirmed group is preserved when server list omits it', () async {
      final repo = TestableHttpChatRepository();

      final cConfirmed = createTestConversation(
        id: 'c1',
        title: 'Confirmed Chat',
        messageId: 100,
        lastAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );

      // Local optimistic group creation (no lastMessageId, created recently)
      final cOptimisticGroup = Conversation(
        id: 'group_new',
        type: 'group',
        title: 'New Study Group',
        lastMessageId: null,
        lastMessageContent: null,
        createdAt: DateTime.now(),
      );

      // Seed cache with both
      await repo.persistConversations([cConfirmed, cOptimisticGroup]);

      final networkCompleter = Completer<Map<String, dynamic>>();
      repo.fetchHandler = (endpoint, query) => networkCompleter.future;

      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: ChatSyncCoordinator.instance,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect((viewModel.conversationsBloc.state as SuccessState<List<Conversation>>).data.length, equals(2));

      // Server has not yet indexed group_new, so it only returns cConfirmed
      networkCompleter.complete({
        'conversations': [cConfirmed.toJson()],
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(state.data.length, equals(2));
      expect(state.data.any((c) => c.id == 'group_new'), isTrue,
          reason: 'Unconfirmed local group must be preserved across server refresh');

      viewModel.dispose();
    });

    test('11. P1: Stale async write is rejected when newer write has already committed', () async {
      final repo = TestableHttpChatRepository();

      final cInitial = createTestConversation(id: 'c1', title: 'Snapshot 1 (Stale)');
      final cNewer = createTestConversation(id: 'c1', title: 'Snapshot 2 (Newer)');

      // Commit newer revision (rev 2) first
      await repo.cache.cacheResponse(
        endpoint: ChatEndpoints.conversations(),
        data: {'conversations': [cNewer.toJson()]},
        writeRevision: 2,
      );

      // Attempt to commit older revision (rev 1) afterwards
      await repo.cache.cacheResponse(
        endpoint: ChatEndpoints.conversations(),
        data: {'conversations': [cInitial.toJson()]},
        writeRevision: 1,
      );

      // Cache must still hold Snapshot 2, not Snapshot 1!
      final cachedRaw = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
      );
      final list = cachedRaw!['conversations'] as List;
      expect(list.first['title'], equals('Snapshot 2 (Newer)'));
    });

    test('12. Lifecycle: Disposed ChatViewModel rejects events and does not emit or persist', () async {
      final repo = TestableHttpChatRepository();
      repo.fetchHandler = (endpoint, query) async => {'conversations': []};

      final viewModel = ChatViewModel(
        repository: repo,
        syncCoordinator: ChatSyncCoordinator.instance,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));

      viewModel.dispose();
      expect(viewModel.isDisposed, isTrue);
      expect(viewModel.conversationsBloc.isClosed, isTrue);
      expect(viewModel.allUsersBloc.isClosed, isTrue);

      // Trigger socket event after disposal — must not throw or emit
      viewModel.handleSocketEventForTesting({
        'type': 'new_message',
        'payload': {
          'conversation_id': 'c_post_dispose',
          'id': 1234,
          'content': 'Should be ignored',
        },
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Refresh after dispose must be no-op
      await viewModel.refreshConversations();
    });

    test('13. P0: User A logout with pending cache clear coordinates with User B login so User B cache is not wiped', () async {
      final repo = TestableHttpChatRepository();

      // Log in User A
      AuthSession.adopt(
        LoginResponse(
          token: 'token_user_a',
          user: User(id: 101, name: 'User A'),
        ),
      );

      final cUserA = createTestConversation(id: 'cA', title: 'User A Chat');
      await repo.persistConversations([cUserA]);

      // Verify User A's cache is present in Hive
      final cachedA = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
      );
      expect(cachedA, isNotNull);
      final listA = cachedA!['conversations'] as List;
      expect(listA.first['title'], equals('User A Chat'));

      // Install a hold on the background cache clear to reproduce the race
      final clearHold = Completer<void>();
      CacheManager.clearHoldCompleter = clearHold;

      // User A logs out — triggers clearAllCache() which pauses at clearHold
      AuthSession.clear();

      // Verify clear is actively in flight
      expect(clearHold.isCompleted, isFalse);

      // User B logs in while cache clear is still pending
      AuthSession.adopt(
        LoginResponse(
          token: 'token_user_b',
          user: User(id: 202, name: 'User B'),
        ),
      );

      // User B persists conversations while User A's clear is still in flight
      final cUserB = createTestConversation(id: 'cB', title: 'User B Chat');
      final userBWriteFuture = repo.persistConversations([cUserB]);

      // Release the clear hold so User A's clear completes
      clearHold.complete();

      // Wait for User B's write and User A's clear to complete
      await userBWriteFuture;
      await AuthSession.pendingClearFuture;

      // Verify User B's newly written cache is NOT wiped!
      final cachedB = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
      );
      expect(cachedB, isNotNull, reason: 'User B cache write must not be wiped by User A clear');
      final listB = cachedB!['conversations'] as List;
      expect(listB.length, equals(1));
      expect(listB.first['title'], equals('User B Chat'));

      // Verify User A's old cache IS wiped
      final cachedAAfter = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
        targetUserScope: '101',
        allowExpired: true,
      );
      expect(cachedAAfter, isNull, reason: 'User A cache must be wiped after logout');

      // Verify guest cache is empty
      final cachedGuest = await repo.cache.getResponse(
        endpoint: ChatEndpoints.conversations(),
        targetUserScope: 'guest',
        allowExpired: true,
      );
      expect(cachedGuest, isNull);
    });

    test('14. True Disk Persistence: Survives Hive box close and reopen, restores offline, preserves account isolation', () async {
      final isolatedDir = await Directory.systemTemp.createTemp('disk_cold_start_test_');

      try {
        // Step 1: Initialize isolated Hive storage
        await Hive.close();
        HiveInitializer.resetForTesting();
        CacheManager().resetForTesting();
        HttpChatRepository.resetWriteSequencingForTesting();
        CacheManager.cacheScopeResolver = () => 'test_scope';
        CacheManager.userScopeResolver =
            () => AuthSession.tokens?.user?.id?.toString() ?? 'guest';
        await HiveInitializer.ensureInitialized(isolatedDir.path);

        // Step 2: Instance 1 writes User A's cache to disk
        AuthSession.adopt(
          LoginResponse(
            token: 'token_user_a',
            user: User(id: 101, name: 'User A'),
          ),
        );

        final repo1 = TestableHttpChatRepository();
        final now = DateTime.now();
        final c1 = createTestConversation(
          id: 'c1',
          title: 'Disk Chat 1',
          lastAt: now.add(const Duration(minutes: 5)),
        );
        final c2 = createTestConversation(
          id: 'c2',
          title: 'Disk Chat 2',
          lastAt: now,
        );

        await repo1.persistConversations([c1, c2]);

        final rawBeforeClose = await repo1.cache.getResponse(
          endpoint: ChatEndpoints.conversations(),
        );
        expect(rawBeforeClose, isNotNull);

        // Step 3: Hard close Hive boxes (simulating app process shutdown)
        await Hive.close();
        HiveInitializer.resetForTesting();
        CacheManager().resetForTesting();
        HttpChatRepository.resetWriteSequencingForTesting();

        // Step 4: Instance 2 reopens Hive from the exact same directory (cold start)
        await HiveInitializer.ensureInitialized(isolatedDir.path);
        final repo2 = TestableHttpChatRepository();

        // Network is offline on cold start
        repo2.fetchHandler = (endpoint, query) async {
          throw DioException(
            requestOptions: RequestOptions(path: endpoint),
            type: DioExceptionType.connectionError,
            error: 'Offline on cold start',
          );
        };

        // User A's cached conversations must restore from disk!
        final restored = await repo2.watchConversations().first;
        expect(restored.length, equals(2));
        expect(restored[0].id, equals('c1'));
        expect(restored[0].title, equals('Disk Chat 1'));
        expect(restored[1].id, equals('c2'));
        expect(restored[1].title, equals('Disk Chat 2'));

        // Step 5: Account isolation check after restart
        await AuthSession.clear();

        // User B logs in
        AuthSession.adopt(
          LoginResponse(
            token: 'token_user_b',
            user: User(id: 202, name: 'User B'),
          ),
        );

        // User B must NOT find User A's cached conversations
        final userBCache = await repo2.cache.getResponse(
          endpoint: ChatEndpoints.conversations(),
        );
        expect(userBCache, isNull);

        // When offline, User B must receive a network error rather than User A's cached chats
        await expectLater(
          repo2.watchConversations().first,
          throwsA(isA<DioException>()),
        );
      } finally {
        await AuthSession.clear();
        await Hive.close();
        if (isolatedDir.existsSync()) {
          await isolatedDir.delete(recursive: true);
        }
        HiveInitializer.resetForTesting();
        CacheManager().resetForTesting();
        HttpChatRepository.resetWriteSequencingForTesting();
        // Restore standard test environment for other tests
        CacheManager.cacheScopeResolver = () => 'test_scope';
        CacheManager.userScopeResolver =
            () => AuthSession.tokens?.user?.id?.toString() ?? 'guest';
        await HiveInitializer.ensureInitialized(tempDir.path);
      }
    });
  });
}
