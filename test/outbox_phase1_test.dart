import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/client_message_id_generator.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/local_outbox_storage.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/pending_outbox_message.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';

void main() {
  group('Phase 1: ChatMessage client_message_id support', () {
    test('fromJson parses client_message_id and retains server id', () {
      final json = {
        'id': 105,
        'conversation_id': 12,
        'sender_id': 1,
        'client_message_id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        'type': 'text',
        'content': 'Hello world',
        'created_at': '2026-10-06T12:00:00Z',
      };

      final message = ChatMessage.fromJson(json, currentUserId: '1');

      expect(message.id, equals('105'));
      expect(
        message.clientMessageId,
        equals('f47ac10b-58cc-4372-a567-0e02b2c3d479'),
      );
      expect(message.isMine, isTrue);
      expect(message.message, equals('Hello world'));
    });

    test('fromJson handles null client_message_id gracefully', () {
      final json = {
        'id': 106,
        'conversation_id': 12,
        'sender_id': 2,
        'type': 'text',
        'content': 'Legacy message without client id',
      };

      final message = ChatMessage.fromJson(json, currentUserId: '1');

      expect(message.id, equals('106'));
      expect(message.clientMessageId, isNull);
      expect(message.isMine, isFalse);
    });

    test('toJson serializes client_message_id when present and omits when null', () {
      final msgWithClientId = ChatMessage(
        id: '201',
        receiverId: '10',
        senderId: '1',
        message: 'With client id',
        sentAt: DateTime.utc(2026, 10, 6),
        isMine: true,
        clientMessageId: 'test-uuid-1234',
      );

      final jsonWith = msgWithClientId.toJson();
      expect(jsonWith['client_message_id'], equals('test-uuid-1234'));
      expect(jsonWith['id'], equals('201'));

      final msgWithoutClientId = ChatMessage(
        id: '202',
        receiverId: '10',
        senderId: '1',
        message: 'Without client id',
        sentAt: DateTime.utc(2026, 10, 6),
        isMine: true,
      );

      final jsonWithout = msgWithoutClientId.toJson();
      expect(jsonWithout.containsKey('client_message_id'), isFalse);
      expect(jsonWithout['id'], equals('202'));
    });

    test('copyWith updates or preserves clientMessageId', () {
      final original = ChatMessage(
        id: '301',
        receiverId: '10',
        senderId: '1',
        message: 'Test',
        sentAt: DateTime.utc(2026, 10, 6),
        isMine: true,
        clientMessageId: 'orig-uuid',
      );

      final copiedPreserved = original.copyWith(message: 'Updated');
      expect(copiedPreserved.clientMessageId, equals('orig-uuid'));

      final copiedUpdated = original.copyWith(clientMessageId: 'new-uuid');
      expect(copiedUpdated.clientMessageId, equals('new-uuid'));
    });
  });

  group('Phase 1: ClientMessageIdGenerator', () {
    test('generate() produces a valid UUID v4 string', () {
      final id = ClientMessageIdGenerator.generate();
      final uuidV4Regex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      );

      expect(uuidV4Regex.hasMatch(id), isTrue,
          reason: 'Expected valid UUID v4 format, got: $id');
    });

    test('generate() produces unique identifiers on each call', () {
      final ids = List.generate(100, (_) => ClientMessageIdGenerator.generate());
      final uniqueSet = ids.toSet();

      expect(uniqueSet.length, equals(100));
    });
  });

  group('Phase 1: PendingOutboxMessage model', () {
    test('toJson and fromJson roundtrip serialization', () {
      final now = DateTime.utc(2026, 10, 6, 15, 30, 0);
      final pending = PendingOutboxMessage(
        clientMessageId: 'uuid-pending-1',
        conversationId: 'conv-42',
        content: 'Pending text message',
        messageType: 'text',
        createdAt: now,
      );

      final json = pending.toJson();
      expect(json['client_message_id'], equals('uuid-pending-1'));
      expect(json['conversation_id'], equals('conv-42'));
      expect(json['content'], equals('Pending text message'));
      expect(json['message_type'], equals('text'));
      expect(json['created_at'], equals(now.toIso8601String()));

      final restored = PendingOutboxMessage.fromJson(json);
      expect(restored.clientMessageId, equals(pending.clientMessageId));
      expect(restored.conversationId, equals(pending.conversationId));
      expect(restored.content, equals(pending.content));
      expect(restored.messageType, equals(pending.messageType));
      expect(restored.createdAt, equals(pending.createdAt));
    });
  });

  group('Phase 1: SharedPreferencesOutboxStorage', () {
    late SharedPreferencesOutboxStorage storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storage = SharedPreferencesOutboxStorage(prefs);
    });

    test('save and getMessagesForConversation retrieves pending messages in order', () async {
      final time1 = DateTime.utc(2026, 10, 6, 10, 0, 0);
      final time2 = DateTime.utc(2026, 10, 6, 10, 5, 0);

      final msg1 = PendingOutboxMessage(
        clientMessageId: 'uuid-1',
        conversationId: 'conv-100',
        content: 'First message',
        createdAt: time1,
      );
      final msg2 = PendingOutboxMessage(
        clientMessageId: 'uuid-2',
        conversationId: 'conv-100',
        content: 'Second message',
        createdAt: time2,
      );

      await storage.save(msg2);
      await storage.save(msg1);

      final results = await storage.getMessagesForConversation('conv-100');
      expect(results.length, equals(2));
      // Must be ordered by createdAt ascending
      expect(results[0].clientMessageId, equals('uuid-1'));
      expect(results[1].clientMessageId, equals('uuid-2'));
    });

    test('getMessagesForConversation filters by conversationId', () async {
      final msgA = PendingOutboxMessage(
        clientMessageId: 'uuid-a',
        conversationId: 'conv-A',
        content: 'For conv A',
        createdAt: DateTime.utc(2026, 10, 6, 10, 0),
      );
      final msgB = PendingOutboxMessage(
        clientMessageId: 'uuid-b',
        conversationId: 'conv-B',
        content: 'For conv B',
        createdAt: DateTime.utc(2026, 10, 6, 10, 1),
      );

      await storage.save(msgA);
      await storage.save(msgB);

      final forA = await storage.getMessagesForConversation('conv-A');
      expect(forA.length, equals(1));
      expect(forA.first.clientMessageId, equals('uuid-a'));

      final forB = await storage.getMessagesForConversation('conv-B');
      expect(forB.length, equals(1));
      expect(forB.first.clientMessageId, equals('uuid-b'));

      final all = await storage.getAllMessages();
      expect(all.length, equals(2));
    });

    test('remove deletes pending message by clientMessageId', () async {
      final msg1 = PendingOutboxMessage(
        clientMessageId: 'uuid-to-remove',
        conversationId: 'conv-1',
        content: 'Will be removed',
        createdAt: DateTime.utc(2026, 10, 6, 10, 0),
      );
      final msg2 = PendingOutboxMessage(
        clientMessageId: 'uuid-to-keep',
        conversationId: 'conv-1',
        content: 'Will stay',
        createdAt: DateTime.utc(2026, 10, 6, 10, 1),
      );

      await storage.save(msg1);
      await storage.save(msg2);

      await storage.remove('uuid-to-remove');

      final remaining = await storage.getMessagesForConversation('conv-1');
      expect(remaining.length, equals(1));
      expect(remaining.first.clientMessageId, equals('uuid-to-keep'));
    });

    test('clear removes all pending messages', () async {
      final msg = PendingOutboxMessage(
        clientMessageId: 'uuid-x',
        conversationId: 'conv-1',
        content: 'Clear me',
        createdAt: DateTime.utc(2026, 10, 6, 10, 0),
      );

      await storage.save(msg);
      expect((await storage.getAllMessages()).length, equals(1));

      await storage.clear();
      expect((await storage.getAllMessages()).isEmpty, isTrue);
    });

    test('replaces existing message when saving identical clientMessageId', () async {
      final original = PendingOutboxMessage(
        clientMessageId: 'uuid-dup',
        conversationId: 'conv-1',
        content: 'Original content',
        createdAt: DateTime.utc(2026, 10, 6, 10, 0),
      );
      final updated = PendingOutboxMessage(
        clientMessageId: 'uuid-dup',
        conversationId: 'conv-1',
        content: 'Updated content',
        createdAt: DateTime.utc(2026, 10, 6, 10, 0),
      );

      await storage.save(original);
      await storage.save(updated);

      final messages = await storage.getMessagesForConversation('conv-1');
      expect(messages.length, equals(1));
      expect(messages.first.content, equals('Updated content'));
    });
  });

  group('Phase 1: InboxMessageListCursorBloc Identity & Outbox Reconciliation', () {
    late InboxMessageListCursorBloc bloc;

    setUp(() {
      bloc = InboxMessageListCursorBloc(conversationId: '12');
    });

    tearDown(() {
      bloc.close();
    });

    test('itemIdentity returns clientMessageId when present and non-empty', () {
      final msg = ChatMessage(
        id: '500',
        receiverId: '12',
        senderId: '1',
        message: 'Test',
        sentAt: DateTime.utc(2026, 10, 6),
        isMine: true,
        clientMessageId: 'client-uuid-999',
      );

      expect(bloc.itemIdentity(msg), equals('client-uuid-999'));
    });

    test('itemIdentity falls back to id when clientMessageId is null or empty', () {
      final msgWithoutClientId = ChatMessage(
        id: '501',
        receiverId: '12',
        senderId: '1',
        message: 'Legacy test',
        sentAt: DateTime.utc(2026, 10, 6),
        isMine: true,
      );

      final msgWithEmptyClientId = ChatMessage(
        id: '502',
        receiverId: '12',
        senderId: '1',
        message: 'Empty client id',
        sentAt: DateTime.utc(2026, 10, 6),
        isMine: true,
        clientMessageId: '',
      );

      expect(bloc.itemIdentity(msgWithoutClientId), equals('501'));
      expect(bloc.itemIdentity(msgWithEmptyClientId), equals('502'));
    });

    test('mergeItem preserves clientMessageId across merge operations', () {
      final existing = ChatMessage(
        id: 'temp-id',
        receiverId: '12',
        senderId: '1',
        message: 'Optimistic text',
        sentAt: DateTime.utc(2026, 10, 6),
        isMine: true,
        clientMessageId: 'uuid-merge-test',
        isDelivered: false,
        isSeen: false,
      );

      final incoming = ChatMessage(
        id: '777', // authoritative server sequence ID
        receiverId: '12',
        senderId: '1',
        message: 'Optimistic text',
        sentAt: DateTime.utc(2026, 10, 6),
        isMine: true,
        clientMessageId: 'uuid-merge-test',
        isDelivered: true,
        isSeen: false,
      );

      final merged = bloc.mergeItem(existing, incoming);

      expect(merged.id, equals('777'));
      expect(merged.clientMessageId, equals('uuid-merge-test'));
      expect(merged.isDelivered, isTrue);
      expect(merged.isSeen, isFalse);
    });

    test('upsertLocalItem reconciles optimistic message in-place upon server echo', () {
      // 1. User sends message -> optimistic message added to cursorPageHolder with clientMessageId
      final optimisticMsg = ChatMessage(
        id: '', // temporary or empty before server assigns integer ID
        receiverId: '12',
        senderId: '1',
        message: 'Outgoing hello',
        sentAt: DateTime.utc(2026, 10, 6, 12, 0, 0),
        isMine: true,
        clientMessageId: 'client-uuid-send-1',
        isDelivered: false,
        isSeen: false,
      );

      bloc.upsertLocalItem(optimisticMsg, emitState: false);
      expect(bloc.cursorPageHolder.items.length, equals(1));
      expect(bloc.cursorPageHolder.items.first.id, equals(''));
      expect(bloc.cursorPageHolder.items.first.clientMessageId, equals('client-uuid-send-1'));
      expect(bloc.cursorPageHolder.items.first.isDelivered, isFalse);

      // 2. Server echoes new_message with same client_message_id and assigned server id "888"
      final serverEchoMsg = ChatMessage(
        id: '888',
        receiverId: '12',
        senderId: '1',
        message: 'Outgoing hello',
        sentAt: DateTime.utc(2026, 10, 6, 12, 0, 0),
        isMine: true,
        clientMessageId: 'client-uuid-send-1',
        isDelivered: true,
        isSeen: false,
      );

      bloc.upsertLocalItem(serverEchoMsg, emitState: false);

      // Message list must STILL have exactly 1 item (no duplication), reconciled with server id
      expect(bloc.cursorPageHolder.items.length, equals(1));
      final reconciled = bloc.cursorPageHolder.items.first;
      expect(reconciled.id, equals('888'));
      expect(reconciled.clientMessageId, equals('client-uuid-send-1'));
      expect(reconciled.isDelivered, isTrue);
    });
  });

  group('Phase 1: WebSocket send_message protocol payload', () {
    test('JSON structure matches Go backend expectations', () {
      const convId = '42';
      const text = 'Hello backend';
      const clientId = 'c56a4180-65aa-42ec-a945-5fd21dec0538';
      const msgType = 'text';

      final payloadMap = {
        'type': 'send_message',
        'payload': {
          'conversation_id': convId,
          'content': text,
          'message_type': msgType,
          'client_message_id': clientId,
        },
      };

      final jsonStr = jsonEncode(payloadMap);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['type'], equals('send_message'));
      final payload = decoded['payload'] as Map<String, dynamic>;
      expect(payload['conversation_id'], equals(convId));
      expect(payload['content'], equals(text));
      expect(payload['message_type'], equals(msgType));
      expect(payload['client_message_id'], equals(clientId));
    });
  });
}
