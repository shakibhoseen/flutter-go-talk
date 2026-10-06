import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';
import 'package:whatsapp_flutter_go/feature/login/model/login_response.dart';

void main() {
  setUp(() {
    AuthSession.adopt(
      LoginResponse(
        token: 'token',
        refreshToken: 'refresh',
        user: User(id: 1, name: 'Current User', email: 'user@test.com'),
      ),
    );
  });

  group('Phase 4: ChatMessage.fromJson status semantics', () {
    test('readCount > 0 does NOT make isSeen true if is_seen is false', () {
      final json = {
        'id': 100,
        'conversation_id': 'conv_group',
        'sender_id': 1,
        'content': 'Hello group',
        'created_at': '2026-10-06T12:00:00Z',
        'is_delivered': false,
        'is_seen': false,
        'read_count': 2,
        'read_by': [
          {'user_id': 2, 'name': 'Bob', 'avatar_url': ''},
          {'user_id': 3, 'name': 'Charlie', 'avatar_url': ''},
        ],
      };

      final message = ChatMessage.fromJson(json, currentUserId: '1');

      expect(message.isSeen, isFalse, reason: 'Partial group reads must not mark message as Seen');
      expect(message.readCount, equals(2));
      expect(message.readBy.length, equals(2));
    });

    test('is_seen == true makes both isSeen and isDelivered true', () {
      final json = {
        'id': 101,
        'conversation_id': 'conv_1',
        'sender_id': 1,
        'content': 'Fully read message',
        'created_at': '2026-10-06T12:00:00Z',
        'is_delivered': false,
        'is_seen': true,
        'read_count': 0,
      };

      final message = ChatMessage.fromJson(json, currentUserId: '1');

      expect(message.isSeen, isTrue);
      expect(message.isDelivered, isTrue, reason: 'Seen implies delivered');
    });

    test('is_delivered == true with is_seen == false', () {
      final json = {
        'id': 102,
        'conversation_id': 'conv_1',
        'sender_id': 1,
        'content': 'Delivered message',
        'created_at': '2026-10-06T12:00:00Z',
        'is_delivered': true,
        'is_seen': false,
      };

      final message = ChatMessage.fromJson(json, currentUserId: '1');

      expect(message.isDelivered, isTrue);
      expect(message.isSeen, isFalse);
    });
  });

  group('Phase 5: Group Watermark Resolution in InboxMessageListCursorBloc', () {
    test('1-to-1: resolves seen when other user watermark >= messageId', () {
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'direct_conv',
        isGroup: false,
      );

      final msg1 = ChatMessage(
        id: '100',
        senderId: '1',
        receiverId: 'direct_conv',
        message: 'Direct 1',
        sentAt: DateTime.now(),
        isMine: true,
        isSeen: false,
        isDelivered: false,
      );
      final msg2 = ChatMessage(
        id: '150',
        senderId: '1',
        receiverId: 'direct_conv',
        message: 'Direct 2',
        sentAt: DateTime.now(),
        isMine: true,
        isSeen: false,
        isDelivered: false,
      );

      bloc.replaceLocalItems([msg2, msg1]);

      // Other user (id: 2) seen watermark moves to 120
      bloc.handleMemberWatermark(
        userId: 2,
        messageId: 120,
        profile: const ReadReceiptUser(userId: 2, name: 'Alice', avatarUrl: ''),
      );

      final items = bloc.cursorPageHolder.items;
      final resolvedMsg1 = items.firstWhere((m) => m.id == '100');
      final resolvedMsg2 = items.firstWhere((m) => m.id == '150');

      expect(resolvedMsg1.isSeen, isTrue, reason: '100 <= 120 in 1-to-1 should be seen');
      expect(resolvedMsg1.isDelivered, isTrue);
      expect(resolvedMsg2.isSeen, isFalse, reason: '150 > 120 should not be seen');
    });

    test('Group with groupMemberIds: message is Seen ONLY when ALL other members have read it', () {
      // Group with members 1 (me), 2, 3
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'group_conv',
        isGroup: true,
        groupMemberIds: {1, 2, 3},
      );

      final msg40 = ChatMessage(
        id: '40',
        senderId: '1',
        receiverId: 'group_conv',
        message: 'Msg 40',
        sentAt: DateTime.now(),
        isMine: true,
        isSeen: false,
        isDelivered: false,
      );
      final msg75 = ChatMessage(
        id: '75',
        senderId: '1',
        receiverId: 'group_conv',
        message: 'Msg 75',
        sentAt: DateTime.now(),
        isMine: true,
        isSeen: false,
        isDelivered: false,
      );
      final msg100 = ChatMessage(
        id: '100',
        senderId: '1',
        receiverId: 'group_conv',
        message: 'Msg 100',
        sentAt: DateTime.now(),
        isMine: true,
        isSeen: false,
        isDelivered: false,
      );

      bloc.replaceLocalItems([msg100, msg75, msg40]);

      // Member 2 reads up to 100
      bloc.handleMemberWatermark(
        userId: 2,
        messageId: 100,
        profile: const ReadReceiptUser(userId: 2, name: 'Bob', avatarUrl: ''),
      );

      // Member 3 has read up to 50
      bloc.handleMemberWatermark(
        userId: 3,
        messageId: 50,
        profile: const ReadReceiptUser(userId: 3, name: 'Charlie', avatarUrl: ''),
      );

      var items = bloc.cursorPageHolder.items;
      var resolved40 = items.firstWhere((m) => m.id == '40');
      var resolved75 = items.firstWhere((m) => m.id == '75');
      var resolved100 = items.firstWhere((m) => m.id == '100');

      // 40: Member 2 (100) >= 40 and Member 3 (50) >= 40 -> BOTH read it -> Seen!
      expect(resolved40.isSeen, isTrue);
      // 75: Member 2 (100) >= 75, but Member 3 (50) < 75 -> NOT ALL read it -> NOT Seen!
      expect(resolved75.isSeen, isFalse);
      // 100: Member 3 (50) < 100 -> NOT Seen!
      expect(resolved100.isSeen, isFalse);

      // Now Member 3 catches up to 100
      bloc.handleMemberWatermark(
        userId: 3,
        messageId: 100,
        profile: const ReadReceiptUser(userId: 3, name: 'Charlie', avatarUrl: ''),
      );

      items = bloc.cursorPageHolder.items;
      resolved75 = items.firstWhere((m) => m.id == '75');
      resolved100 = items.firstWhere((m) => m.id == '100');

      // Now all members (2 and 3) are at 100 -> all messages up to 100 are Seen!
      expect(resolved75.isSeen, isTrue);
      expect(resolved100.isSeen, isTrue);
    });

    test('Group with unknown member set: does NOT guess and preserves server isSeen', () {
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'group_conv_no_members',
        isGroup: true,
        // groupMemberIds not provided
      );

      final msg = ChatMessage(
        id: '100',
        senderId: '1',
        receiverId: 'group_conv_no_members',
        message: 'Msg',
        sentAt: DateTime.now(),
        isMine: true,
        isSeen: false,
        isDelivered: false,
      );

      bloc.replaceLocalItems([msg]);

      // Watermark arrives for user 2
      bloc.handleMemberWatermark(
        userId: 2,
        messageId: 100,
        profile: const ReadReceiptUser(userId: 2, name: 'Bob', avatarUrl: ''),
      );

      final resolved = bloc.cursorPageHolder.items.first;
      expect(resolved.isSeen, isFalse, reason: 'Must not guess when member set is incomplete');
    });

    test('Exact watermark-head avatars: getWatermarkUsers only returns users at that exact head', () {
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'group_bubbles',
        isGroup: true,
        groupMemberIds: {1, 2, 3},
      );

      // User 2 watermark at 50
      bloc.handleMemberWatermark(
        userId: 2,
        messageId: 50,
        profile: const ReadReceiptUser(userId: 2, name: 'Bob', avatarUrl: ''),
      );

      expect(bloc.getWatermarkUsers('50').map((u) => u.userId), contains(2));
      expect(bloc.getWatermarkUsers('49'), isEmpty);

      // User 2 watermark advances to 100
      bloc.handleMemberWatermark(
        userId: 2,
        messageId: 100,
        profile: const ReadReceiptUser(userId: 2, name: 'Bob', avatarUrl: ''),
      );

      // User 2 must NO LONGER appear at 50, but ONLY at 100!
      expect(bloc.getWatermarkUsers('50'), isEmpty);
      expect(bloc.getWatermarkUsers('100').map((u) => u.userId), contains(2));
    });

    test('Monotonic watermark: older watermark does not regress existing watermark', () {
      final bloc = InboxMessageListCursorBloc(
        conversationId: 'monotonic_conv',
        isGroup: true,
        groupMemberIds: {1, 2},
      );

      bloc.updateMemberWatermark(userId: 2, messageId: 100);
      expect(bloc.userLastMessageSeenID[2], equals(100));

      // Stale event with older messageId 80
      bloc.updateMemberWatermark(userId: 2, messageId: 80);
      expect(bloc.userLastMessageSeenID[2], equals(100), reason: 'Watermark must not regress');
    });
  });

  group('Phase 2 & 3: Seen and Delivered ACK selection logic', () {
    test('Incoming message selection finds newest incoming message even when outgoing message is at top', () {
      final items = [
        // Outgoing message just sent (index 0)
        ChatMessage(
          id: 'temp_outbox_1',
          senderId: '1',
          receiverId: 'conv_1',
          message: 'My recent message',
          sentAt: DateTime.now(),
          isMine: true,
        ),
        // Incoming message from other user (index 1)
        ChatMessage(
          id: '150',
          senderId: '2',
          receiverId: 'conv_1',
          message: 'Hello from Bob',
          sentAt: DateTime.now().subtract(const Duration(seconds: 10)),
          isMine: false,
        ),
        // Older incoming message (index 2)
        ChatMessage(
          id: '140',
          senderId: '2',
          receiverId: 'conv_1',
          message: 'Older message',
          sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
          isMine: false,
        ),
      ];

      // Simulated selection algorithm from _checkAndSendSeenAck
      ChatMessage? latestIncoming;
      for (final item in items) {
        if (!item.isMine && item.id.isNotEmpty) {
          final parsedId = int.tryParse(item.id);
          if (parsedId != null && parsedId > 0) {
            latestIncoming = item;
            break;
          }
        }
      }

      expect(latestIncoming, isNotNull);
      expect(latestIncoming!.id, equals('150'));
      expect(latestIncoming.senderId, equals('2'));
    });

    test('Monotonic check prevents re-acknowledging older incoming message when older pages are prepended to list tail', () {
      String? lastAckedMessageId = '150';

      // Simulating older page loaded (appended to list tail in DESC order)
      final olderIncoming = ChatMessage(
        id: '140',
        senderId: '2',
        receiverId: 'conv_1',
        message: 'Older message from history',
        sentAt: DateTime.now().subtract(const Duration(days: 1)),
        isMine: false,
      );

      final incomingId = int.tryParse(olderIncoming.id) ?? 0;
      final lastAckedId = int.tryParse(lastAckedMessageId) ?? 0;

      final shouldAck = incomingId > 0 && incomingId > lastAckedId;
      expect(shouldAck, isFalse, reason: 'Must not send Seen ACK for older paginated message');
    });
  });
}
