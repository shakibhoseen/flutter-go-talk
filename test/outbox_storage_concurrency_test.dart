import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_outbox_processor.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/local_outbox_storage.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/pending_outbox_message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesOutboxStorage.resetQueueForTesting();
    await AuthSession.clear();
  });

  tearDown(() async {
    SharedPreferencesOutboxStorage.resetQueueForTesting();
    await AuthSession.clear();
  });

  group('CHAT-001: SharedPreferencesOutboxStorage Queue & Concurrency Hardening', () {
    test('1. Serialized FIFO execution: concurrent save, remove, and save without await preserve strict ordering', () async {
      final storage = SharedPreferencesOutboxStorage();

      final msg1 = PendingOutboxMessage(
        clientMessageId: 'fifo-1',
        conversationId: 'c1',
        content: 'Msg 1',
        createdAt: DateTime.utc(2026, 1, 1, 10, 0),
        senderId: 'user_a',
      );
      final msg2 = PendingOutboxMessage(
        clientMessageId: 'fifo-2',
        conversationId: 'c1',
        content: 'Msg 2',
        createdAt: DateTime.utc(2026, 1, 1, 10, 1),
        senderId: 'user_a',
      );

      // Launch operations concurrently without awaiting each one
      final f1 = storage.save(msg1);
      final f2 = storage.save(msg2);
      final f3 = storage.remove('fifo-1');

      await Future.wait([f1, f2, f3]);

      final remaining = await storage.getAllMessages(targetUserScope: 'user_a');
      expect(remaining.length, equals(1));
      expect(remaining.first.clientMessageId, equals('fifo-2'));
    });

    test('2. Race condition fix: concurrent clear for User A does not overwrite concurrent save for User B', () async {
      final storage = SharedPreferencesOutboxStorage();

      // Seed with initial message for User A
      await storage.save(
        PendingOutboxMessage(
          clientMessageId: 'msg-user-a',
          conversationId: 'c1',
          content: 'Secret from A',
          createdAt: DateTime.utc(2026, 1, 1, 10, 0),
          senderId: 'user_a',
        ),
      );

      final msgB = PendingOutboxMessage(
        clientMessageId: 'msg-user-b',
        conversationId: 'c2',
        content: 'Hello from B',
        createdAt: DateTime.utc(2026, 1, 1, 10, 1),
        senderId: 'user_b',
      );

      // Start clearing User A and immediately saving User B concurrently
      final clearFuture = storage.clear(targetUserScope: 'user_a');
      final saveFuture = storage.save(msgB);

      await Future.wait([clearFuture, saveFuture]);

      // User A's messages are gone
      final aMessages = await storage.getAllMessages(targetUserScope: 'user_a');
      expect(aMessages, isEmpty);

      // User B's message was not clobbered by User A's clear
      final bMessages = await storage.getAllMessages(targetUserScope: 'user_b');
      expect(bMessages.length, equals(1));
      expect(bMessages.first.clientMessageId, equals('msg-user-b'));
    });

    test('3. Consistent read snapshot: getAllMessages awaits in-flight queue operations before reading', () async {
      final storage = SharedPreferencesOutboxStorage();

      final msg = PendingOutboxMessage(
        clientMessageId: 'snapshot-msg',
        conversationId: 'c1',
        content: 'Snapshot content',
        createdAt: DateTime.utc(2026, 1, 1, 10, 0),
        senderId: 'user_a',
      );

      // Do NOT await save
      storage.save(msg);

      // getAllMessages() must wait for the queued save and read the consistent state
      final messages = await storage.getAllMessages(targetUserScope: 'user_a');
      expect(messages.length, equals(1));
      expect(messages.first.clientMessageId, equals('snapshot-msg'));
    });

    test('4. Queue error recovery: failure in one queued operation does not block subsequent operations', () async {
      final storage = SharedPreferencesOutboxStorage();

      // Queue an action that triggers a failure
      final failingFuture = storage.save(
        PendingOutboxMessage(
          clientMessageId: 'fail-msg',
          conversationId: 'c1',
          content: 'Failing',
          createdAt: DateTime.utc(2026, 1, 1, 10, 0),
          senderId: 'user_a',
        ),
      );

      // Simulate a successful follow-up action queued behind it
      final successMsg = PendingOutboxMessage(
        clientMessageId: 'success-msg',
        conversationId: 'c1',
        content: 'Success after recovery',
        createdAt: DateTime.utc(2026, 1, 1, 10, 1),
        senderId: 'user_a',
      );
      final successFuture = storage.save(successMsg);

      await Future.wait([failingFuture, successFuture]);

      final all = await storage.getAllMessages(targetUserScope: 'user_a');
      expect(all.any((m) => m.clientMessageId == 'success-msg'), isTrue);
    });

    test('5. Type-safe map handling in clear: decodes Map<dynamic, dynamic> and removes matching user without dropping others', () async {
      // Manually set raw SharedPreferences string containing dynamic maps
      final prefs = await SharedPreferences.getInstance();
      final rawData = {
        'msg-a': {
          'client_message_id': 'msg-a',
          'conversation_id': 'c1',
          'content': 'A text',
          'message_type': 'text',
          'created_at': '2026-01-01T10:00:00.000Z',
          'sender_id': 'user_a',
        },
        'msg-b': {
          'client_message_id': 'msg-b',
          'conversation_id': 'c2',
          'content': 'B text',
          'message_type': 'text',
          'created_at': '2026-01-01T10:01:00.000Z',
          'sender_id': 'user_b',
        },
      };
      await prefs.setString(SharedPreferencesOutboxStorage.storageKey, jsonEncode(rawData));

      final storage = SharedPreferencesOutboxStorage();

      // Clear only User A
      await storage.clear(targetUserScope: 'user_a');

      final aMessages = await storage.getAllMessages(targetUserScope: 'user_a');
      expect(aMessages, isEmpty);

      final bMessages = await storage.getAllMessages(targetUserScope: 'user_b');
      expect(bMessages.length, equals(1));
      expect(bMessages.first.clientMessageId, equals('msg-b'));
    });
  });

  group('CHAT-001: Policy B — Quarantined Persistence & Multi-Account Isolation Invariants', () {
    test('6. Quarantined persistence: User A outbox messages survive logout and recover upon re-login', () async {
      final storage = SharedPreferencesOutboxStorage();

      await storage.save(
        PendingOutboxMessage(
          clientMessageId: 'persist-msg-1',
          conversationId: 'c1',
          content: 'Offline draft from User A',
          createdAt: DateTime.utc(2026, 1, 1, 10, 0),
          senderId: '101',
        ),
      );

      // User A logs out
      await AuthSession.clear();

      // Messages are still preserved on disk (Policy B contract)
      final allPreserved = await storage.getAllMessages();
      expect(allPreserved.length, equals(1));
      expect(allPreserved.first.clientMessageId, equals('persist-msg-1'));

      // While logged out (scope == guest), User A's messages are quarantined and not visible
      final guestMessages = await storage.getAllMessages(targetUserScope: 'guest');
      expect(guestMessages, isEmpty);

      // User B logs in: User A's messages are not visible to User B
      final userBMessages = await storage.getAllMessages(targetUserScope: '202');
      expect(userBMessages, isEmpty);

      // User A logs back in: User A's messages are intact and recovered
      final userARecovered = await storage.getAllMessages(targetUserScope: '101');
      expect(userARecovered.length, equals(1));
      expect(userARecovered.first.clientMessageId, equals('persist-msg-1'));
      expect(userARecovered.first.content, equals('Offline draft from User A'));
    });

    test('7. Outbox processor strictly ignores quarantined messages of another user or when logged out', () async {
      final storage = SharedPreferencesOutboxStorage();

      await storage.save(
        PendingOutboxMessage(
          clientMessageId: 'user-a-quarantined',
          conversationId: 'c1',
          content: 'Pending from A',
          createdAt: DateTime.utc(2026, 1, 1, 10, 0),
          senderId: '101',
        ),
      );

      final sentMessages = <String>[];
      final processor = ChatOutboxProcessor(
        outboxStorage: storage,
        currentUserScopeProvider: () => '202', // User B is currently authenticated
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required clientMessageId,
          required content,
          required conversationId,
          messageType = 'text',
        }) {
          sentMessages.add(clientMessageId);
        },
      );

      // Process pending under User B: User A's message must NOT be transmitted
      await processor.processPending();
      expect(sentMessages, isEmpty);

      // Process pending while logged out: User A's message must NOT be transmitted
      final loggedOutProcessor = ChatOutboxProcessor(
        outboxStorage: storage,
        currentUserScopeProvider: () => 'guest',
        isConnectedOverride: () => true,
        sendMessageOverride: ({
          required clientMessageId,
          required content,
          required conversationId,
          messageType = 'text',
        }) {
          sentMessages.add(clientMessageId);
        },
      );

      await loggedOutProcessor.processPending();
      expect(sentMessages, isEmpty);
    });
  });
}
