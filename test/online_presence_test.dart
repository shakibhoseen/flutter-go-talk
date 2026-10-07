import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_flutter_go/core/db/network/chat_endpoints.dart';
import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_event_type.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';
import 'package:whatsapp_flutter_go/core/widgets/cute_avatar.dart';
import 'package:whatsapp_flutter_go/feature/home/data/chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_user.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/view_model/chat_view_model.dart';

class _FakeChatRepository implements ChatRepository {
  @override
  Future<List<Conversation>> getConversations() async => [];

  @override
  Future<List<ChatUser>> getAllUsers() async => [];

  @override
  Future<String> getOrCreateDirectConversation(int targetUserId) async => '';

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  }) async =>
      throw UnimplementedError();
}

void main() {
  final now = DateTime.utc(2026, 10, 7, 12, 0);

  group('Online Presence - Model & Constants Tests', () {
    test('ChatEndpoints.presence returns presence endpoint', () {
      expect(ChatEndpoints.presence(), 'presence');
    });

    test('ChatSocketEventType.userPresence is user_presence', () {
      expect(ChatSocketEventType.userPresence, 'user_presence');
    });

    test('Conversation.fromJson correctly parses is_online', () {
      final jsonOnline = {
        'id': 'conv-123',
        'type': 'direct',
        'title': 'Alice',
        'other_user_id': 2,
        'is_online': true,
        'created_at': '2026-10-07T12:00:00Z',
      };
      final convOnline = Conversation.fromJson(jsonOnline);
      expect(convOnline.isOnline, isTrue);
      expect(convOnline.id, 'conv-123');
      expect(convOnline.otherUserId, 2);

      final jsonOffline = {
        'id': 'conv-124',
        'type': 'direct',
        'title': 'Bob',
        'other_user_id': 3,
        'is_online': false,
        'created_at': '2026-10-07T12:00:00Z',
      };
      final convOffline = Conversation.fromJson(jsonOffline);
      expect(convOffline.isOnline, isFalse);

      final jsonOmitted = {
        'id': 'conv-125',
        'type': 'direct',
        'title': 'Charlie',
        'created_at': '2026-10-07T12:00:00Z',
      };
      final convOmitted = Conversation.fromJson(jsonOmitted);
      expect(convOmitted.isOnline, isFalse);
    });

    test('Conversation.toJson includes is_online', () {
      final conv = Conversation(
        id: 'conv-1',
        type: 'direct',
        title: 'Alice',
        isOnline: true,
        createdAt: now,
      );
      final json = conv.toJson();
      expect(json['is_online'], isTrue);
    });

    test('Conversation.copyWith updates isOnline correctly', () {
      final conv = Conversation(
        id: 'conv-1',
        type: 'direct',
        title: 'Alice',
        isOnline: false,
        createdAt: now,
      );
      final updated = conv.copyWith(isOnline: true);
      expect(updated.isOnline, isTrue);
      expect(updated.id, 'conv-1');

      final same = updated.copyWith();
      expect(same.isOnline, isTrue);
    });
  });

  group('Online Presence - CuteAvatar UI Tests', () {
    testWidgets('CuteAvatar renders online dot when isOnline = true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CuteAvatar(
              name: 'Alice',
              isOnline: true,
              showOnlineDot: true,
            ),
          ),
        ),
      );

      final containerFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final box = widget.decoration as BoxDecoration;
          return box.color == AppColors.onlineGreen && box.shape == BoxShape.circle;
        }
        return false;
      });

      expect(containerFinder, findsOneWidget);
    });

    testWidgets('CuteAvatar does NOT render online dot when isOnline = false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CuteAvatar(
              name: 'Alice',
              isOnline: false,
              showOnlineDot: true,
            ),
          ),
        ),
      );

      final containerFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final box = widget.decoration as BoxDecoration;
          return box.color == AppColors.onlineGreen;
        }
        return false;
      });

      expect(containerFinder, findsNothing);
    });
  });

  group('Online Presence - ChatViewModel Real-time Tests', () {
    test('ChatViewModel updates user and conversation status on user_presence socket event', () async {
      final viewModel = ChatViewModel(repository: _FakeChatRepository());

      // Seed initial users and conversations
      final userBob = ChatUser(id: '5', name: 'Bob', avatarUrl: '', isOnline: false);
      final userCharlie = ChatUser(id: '6', name: 'Charlie', avatarUrl: '', isOnline: false);
      viewModel.allUsersBloc.emitSuccess([userBob, userCharlie]);

      final directConv = Conversation(
        id: 'c1',
        type: 'direct',
        title: 'Bob',
        otherUserId: 5,
        isOnline: false,
        createdAt: now,
      );
      final groupConv = Conversation(
        id: 'c2',
        type: 'group',
        title: 'Go Team',
        isOnline: false,
        createdAt: now,
      );
      viewModel.conversationsBloc.emitSuccess([directConv, groupConv]);

      // Emit user_presence event: user 5 goes online
      viewModel.handleSocketEventForTesting({
        'type': 'user_presence',
        'payload': {
          'user_id': 5,
          'is_online': true,
        },
      });

      // Verify allUsersBloc updated
      final usersState1 = viewModel.allUsersBloc.state as SuccessState<List<ChatUser>>;
      expect(usersState1.data.firstWhere((u) => u.id == '5').isOnline, isTrue);
      expect(usersState1.data.firstWhere((u) => u.id == '6').isOnline, isFalse);

      // Verify conversationsBloc updated (direct conversation with user 5 is online, group is unaffected)
      final convsState1 = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(convsState1.data.firstWhere((c) => c.id == 'c1').isOnline, isTrue);
      expect(convsState1.data.firstWhere((c) => c.id == 'c2').isOnline, isFalse);

      // Emit user_presence event: user 5 goes offline
      viewModel.handleSocketEventForTesting({
        'type': 'user_presence',
        'payload': {
          'user_id': 5,
          'is_online': false,
        },
      });

      final usersState2 = viewModel.allUsersBloc.state as SuccessState<List<ChatUser>>;
      expect(usersState2.data.firstWhere((u) => u.id == '5').isOnline, isFalse);

      final convsState2 = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      expect(convsState2.data.firstWhere((c) => c.id == 'c1').isOnline, isFalse);
    });
  });
}
