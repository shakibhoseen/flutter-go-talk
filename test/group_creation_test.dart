import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_flutter_go/core/db/network/chat_endpoints.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/chat_routes.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/feature/group/data/group_repository.dart';
import 'package:whatsapp_flutter_go/feature/group/model/group_member.dart';
import 'package:whatsapp_flutter_go/feature/group/presentation/create_group_screen.dart';
import 'package:whatsapp_flutter_go/feature/home/data/chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_user.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/view_model/chat_view_model.dart';
import 'package:whatsapp_flutter_go/feature/login/model/login_response.dart';

class MockGroupRepository implements GroupRepository {
  bool shouldThrow;
  String convIdToReturn;
  int createGroupCallCount = 0;
  String? lastTitle;
  List<int>? lastMemberIds;
  Completer<String>? completer;

  MockGroupRepository({
    this.shouldThrow = false,
    this.convIdToReturn = 'conv-group-999',
    this.completer,
  });

  @override
  Future<String> createGroup({
    required String title,
    required List<int> memberIds,
  }) async {
    createGroupCallCount++;
    lastTitle = title;
    lastMemberIds = memberIds;
    if (shouldThrow) {
      throw Exception('Server error creating group');
    }
    if (completer != null) {
      return completer!.future;
    }
    return convIdToReturn;
  }

  @override
  Future<String> updateGroupAvatar(String conversationId, File imageFile) async => '';

  @override
  Future<List<GroupMember>> getGroupMembers(String conversationId) async => const [];

  @override
  Future<void> addGroupMember({
    required String conversationId,
    required int userId,
  }) async {}

  @override
  Future<void> removeGroupMember({
    required String conversationId,
    required int userId,
  }) async {}
}

class MockChatRepositoryForGroup implements ChatRepository {
  List<ChatUser> usersToReturn;
  List<Conversation> conversationsToReturn;

  MockChatRepositoryForGroup({
    this.usersToReturn = const [],
    this.conversationsToReturn = const [],
  });

  @override
  Future<List<ChatUser>> getAllUsers() async => usersToReturn;

  @override
  Future<List<Conversation>> getConversations() async => conversationsToReturn;

  @override
  Future<String> getOrCreateDirectConversation(int targetUserId) async => 'direct-id';

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
    NavigationService.navigatorKey = GlobalKey<NavigatorState>();
  });

  group('Group Creation - Endpoints & Models', () {
    test('ChatEndpoints.groupConversation returns correct path', () {
      expect(ChatEndpoints.groupConversation(), equals('conversations/group'));
    });
  });

  group('Group Creation - UI & Flow Tests', () {
    final testUsers = [
      const ChatUser(
        id: '2',
        name: 'User B',
        email: 'userb@test.com',
        avatarUrl: '',
      ),
      const ChatUser(
        id: '3',
        name: 'User C',
        email: 'userc@test.com',
        avatarUrl: '',
      ),
      const ChatUser(
        id: '4',
        name: 'User D',
        email: 'userd@test.com',
        avatarUrl: '',
      ),
    ];

    testWidgets('Empty group title displays validation SnackBar without calling repository', (tester) async {
      final chatRepo = MockChatRepositoryForGroup(usersToReturn: testUsers);
      final viewModel = ChatViewModel(repository: chatRepo);
      final groupRepo = MockGroupRepository();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          navigatorObservers: [NavigationService.observer],
          home: CreateGroupScreen(
            chatViewModel: viewModel,
            groupRepository: groupRepo,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Create Group without title
      await tester.tap(find.text('Create Group'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a group name'), findsOneWidget);
      expect(groupRepo.createGroupCallCount, equals(0));

      viewModel.dispose();
    });

    testWidgets('Zero members selected displays validation SnackBar without calling repository', (tester) async {
      final chatRepo = MockChatRepositoryForGroup(usersToReturn: testUsers);
      final viewModel = ChatViewModel(repository: chatRepo);
      final groupRepo = MockGroupRepository();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          navigatorObservers: [NavigationService.observer],
          home: CreateGroupScreen(
            chatViewModel: viewModel,
            groupRepository: groupRepo,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter group title but don't select any member
      await tester.enterText(find.byType(TextField), 'Flutter Devs');
      await tester.tap(find.text('Create Group'));
      await tester.pumpAndSettle();

      expect(find.text('Please select at least 1 member'), findsOneWidget);
      expect(groupRepo.createGroupCallCount, equals(0));

      viewModel.dispose();
    });

    testWidgets('Multiple member selection toggles selection and updates count', (tester) async {
      final chatRepo = MockChatRepositoryForGroup(usersToReturn: testUsers);
      final viewModel = ChatViewModel(repository: chatRepo);
      final groupRepo = MockGroupRepository();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          navigatorObservers: [NavigationService.observer],
          home: CreateGroupScreen(
            chatViewModel: viewModel,
            groupRepository: groupRepo,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('0 selected'), findsOneWidget);

      // Select User B
      await tester.tap(find.text('User B'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      // Select User C
      await tester.tap(find.text('User C'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      // Deselect User B
      await tester.tap(find.text('User B'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      viewModel.dispose();
    });

    testWidgets('Successful create navigates to ChatInboxScreen with group Conversation', (tester) async {
      final chatRepo = MockChatRepositoryForGroup(usersToReturn: testUsers);
      final viewModel = ChatViewModel(repository: chatRepo);
      final groupRepo = MockGroupRepository(convIdToReturn: 'conv-group-888');
      Conversation? receivedConversation;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          navigatorObservers: [NavigationService.observer],
          onGenerateRoute: (settings) {
            if (settings.name == ChatRoutes.inbox) {
              receivedConversation = settings.arguments as Conversation?;
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const Scaffold(body: Text('ChatInboxScreenStub')),
              );
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => CreateGroupScreen(
                chatViewModel: viewModel,
                groupRepository: groupRepo,
              ),
            );
          },
          home: CreateGroupScreen(
            chatViewModel: viewModel,
            groupRepository: groupRepo,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter group title
      await tester.enterText(find.byType(TextField), 'Project Team');
      // Select User B and User D
      await tester.tap(find.text('User B'));
      await tester.tap(find.text('User D'));
      await tester.pumpAndSettle();

      // Tap Create
      await tester.tap(find.text('Create Group'));
      await tester.pumpAndSettle();

      // Verify repository call
      expect(groupRepo.createGroupCallCount, equals(1));
      expect(groupRepo.lastTitle, equals('Project Team'));
      expect(groupRepo.lastMemberIds, containsAll([2, 4]));

      // Verify navigation to inbox
      expect(find.text('ChatInboxScreenStub'), findsOneWidget);
      expect(receivedConversation, isNotNull);
      expect(receivedConversation!.id, equals('conv-group-888'));
      expect(receivedConversation!.type, equals('group'));
      expect(receivedConversation!.title, equals('Project Team'));
      expect(receivedConversation!.isGroup, isTrue);

      // Verify conversation is immediately added to ChatViewModel's conversations list (Bug 1 fix)
      final convState = viewModel.conversationsBloc.state;
      expect(convState, isA<SuccessState<List<Conversation>>>());
      final convs = (convState as SuccessState<List<Conversation>>).data;
      expect(convs.any((c) => c.id == 'conv-group-888' && c.title == 'Project Team'), isTrue);

      viewModel.dispose();
    });

    testWidgets('Duplicate tap on create button is prevented while in-flight', (tester) async {
      final completer = Completer<String>();
      final chatRepo = MockChatRepositoryForGroup(usersToReturn: testUsers);
      final viewModel = ChatViewModel(repository: chatRepo);
      final groupRepo = MockGroupRepository(completer: completer);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          navigatorObservers: [NavigationService.observer],
          home: CreateGroupScreen(
            chatViewModel: viewModel,
            groupRepository: groupRepo,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Concurrent Test');
      await tester.tap(find.text('User B'));
      await tester.pumpAndSettle();

      // First tap
      await tester.tap(find.text('Create Group'));
      await tester.pump(); // Start async work, spinner appears

      expect(groupRepo.createGroupCallCount, equals(1));

      // Second tap while still in flight
      await tester.tap(find.text('Creating...'));
      await tester.pump();

      // Call count must remain 1
      expect(groupRepo.createGroupCallCount, equals(1));

      // Complete future
      completer.complete('conv-group-concurrent');
      await tester.pumpAndSettle();

      viewModel.dispose();
    });

    testWidgets('API failure displays error SnackBar with Retry button', (tester) async {
      final chatRepo = MockChatRepositoryForGroup(usersToReturn: testUsers);
      final viewModel = ChatViewModel(repository: chatRepo);
      final groupRepo = MockGroupRepository(shouldThrow: true);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          navigatorObservers: [NavigationService.observer],
          home: CreateGroupScreen(
            chatViewModel: viewModel,
            groupRepository: groupRepo,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Failing Group');
      await tester.tap(find.text('User B'));
      await tester.pumpAndSettle();

      // Tap Create
      await tester.tap(find.text('Create Group'));
      await tester.pumpAndSettle();

      expect(groupRepo.createGroupCallCount, equals(1));
      expect(find.textContaining('Failed to create group'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Fix repo and tap Retry
      groupRepo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(groupRepo.createGroupCallCount, equals(2));

      viewModel.dispose();
    });
  });

  group('Group Creation & Conversation List - Bug 1 & Bug 2 Tests', () {
    test('Bug 1: Group created with no message immediately appears in conversation list', () async {
      final chatRepo = MockChatRepositoryForGroup();
      final viewModel = ChatViewModel(repository: chatRepo);

      // Initially empty or loaded
      await pumpEventQueue();

      final newGroup = Conversation(
        id: 'conv-group-100',
        type: 'group',
        title: 'Dev Team',
        createdAt: DateTime.now(),
      );

      // Group creation calls addOrUpdateConversation
      viewModel.addOrUpdateConversation(newGroup);

      final state = viewModel.conversationsBloc.state;
      expect(state, isA<SuccessState<List<Conversation>>>());
      final convs = (state as SuccessState<List<Conversation>>).data;

      expect(convs.length, equals(1));
      expect(convs.first.id, equals('conv-group-100'));
      expect(convs.first.type, equals('group'));
      expect(convs.first.title, equals('Dev Team'));
      expect(convs.first.displayTitle, equals('Dev Team'));
      expect(convs.first.lastMessageContent, isNull);
      expect(convs.first.isGroup, isTrue);

      viewModel.dispose();
    });

    test('Bug 2: Message sent in group keeps conversation title as the group title (not sender name)', () async {
      final chatRepo = MockChatRepositoryForGroup();
      final viewModel = ChatViewModel(repository: chatRepo);

      await pumpEventQueue();

      // Group exists in conversation list
      final group = Conversation(
        id: 'conv-group-100',
        type: 'group',
        title: 'Flutter Devs',
        createdAt: DateTime.now(),
      );
      viewModel.addOrUpdateConversation(group);

      // Simulate logged-in user (or sender) sending a message in the group
      final payload = {
        'id': 555,
        'conversation_id': 'conv-group-100',
        'conversation_type': 'group',
        'content': 'First message in group',
        'sender_id': 1,
        'sender_name': 'Logged In User',
        'created_at': DateTime.now().toIso8601String(),
      };

      viewModel.handleNewMessageForTest(payload);

      final state = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      final updatedGroup = state.data.firstWhere((c) => c.id == 'conv-group-100');

      // Title must remain group title, NOT sender name!
      expect(updatedGroup.title, equals('Flutter Devs'));
      expect(updatedGroup.displayTitle, equals('Flutter Devs'));
      expect(updatedGroup.title, isNot(equals('Logged In User')));
      // Message preview must be updated
      expect(updatedGroup.lastMessageContent, equals('First message in group'));
      expect(updatedGroup.lastMessageId, equals(555));
      expect(updatedGroup.lastMessageSenderId, equals(1));

      viewModel.dispose();
    });

    test('Bug 2: Message arriving for an un-fetched group conversation never sets group title to sender name', () async {
      final chatRepo = MockChatRepositoryForGroup();
      final viewModel = ChatViewModel(repository: chatRepo);

      await pumpEventQueue();

      // Brand new group message arriving over WebSocket before GET /conversations
      final payload = {
        'id': 777,
        'conversation_id': 'conv-group-unfetched',
        'conversation_type': 'group',
        'content': 'Welcome everyone!',
        'sender_id': 2,
        'sender_name': 'Alice',
        'created_at': DateTime.now().toIso8601String(),
      };

      viewModel.handleNewMessageForTest(payload);

      final state = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      final conv = state.data.firstWhere((c) => c.id == 'conv-group-unfetched');

      // Group title must NEVER be the sender's name
      expect(conv.title, isNot(equals('Alice')));
      expect(conv.displayTitle, equals('Group chat'));
      expect(conv.lastMessageContent, equals('Welcome everyone!'));

      viewModel.dispose();
    });

    test('Bug 2 & Monotonic Merge: refreshConversations preserves authoritative server group title when local message is newer', () async {
      // In-memory conversation has newer message (id: 200), title 'Local Group'
      final localConv = Conversation(
        id: 'conv-group-sync',
        type: 'group',
        title: 'Local Group',
        lastMessageId: 200,
        lastMessageContent: 'Newest local message',
        lastMessageAt: DateTime.utc(2026, 10, 7, 12, 0),
        createdAt: DateTime.utc(2026, 10, 7, 10, 0),
      );

      // Server returns slightly older snapshot (id: 190) with authoritative title 'Authoritative Group Title'
      final serverConv = Conversation(
        id: 'conv-group-sync',
        type: 'group',
        title: 'Authoritative Group Title',
        lastMessageId: 190,
        lastMessageContent: 'Older server message',
        lastMessageAt: DateTime.utc(2026, 10, 7, 11, 0),
        createdAt: DateTime.utc(2026, 10, 7, 10, 0),
      );

      final chatRepo = MockChatRepositoryForGroup(
        conversationsToReturn: [serverConv],
      );
      final viewModel = ChatViewModel(repository: chatRepo);

      await pumpEventQueue();

      // Add local head with newer message
      viewModel.addOrUpdateConversation(localConv);

      // Trigger background refresh
      await viewModel.refreshConversations();

      final state = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      final merged = state.data.firstWhere((c) => c.id == 'conv-group-sync');

      // Monotonic merge keeps newer message data:
      expect(merged.lastMessageId, equals(200));
      expect(merged.lastMessageContent, equals('Newest local message'));
      // BUT preserves the authoritative server group title:
      expect(merged.title, equals('Authoritative Group Title'));
      expect(merged.displayTitle, equals('Authoritative Group Title'));

      viewModel.dispose();
    });

    test('Direct chat title logic remains intact', () async {
      AuthSession.adopt(LoginResponse(
        token: 'test-token',
        user: User(id: 1, name: 'My Own Name'),
      ));

      final chatRepo = MockChatRepositoryForGroup();
      final viewModel = ChatViewModel(repository: chatRepo);

      await pumpEventQueue();

      // 1. Direct message from other user (sender_id: 2) -> title set to Bob
      viewModel.handleNewMessageForTest({
        'id': 101,
        'conversation_id': 'conv-direct-bob',
        'conversation_type': 'direct',
        'content': 'Hi!',
        'sender_id': 2,
        'sender_name': 'Bob',
        'created_at': DateTime.now().toIso8601String(),
      });

      var state = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      var bobConv = state.data.firstWhere((c) => c.id == 'conv-direct-bob');
      expect(bobConv.title, equals('Bob'));
      expect(bobConv.displayTitle, equals('Bob'));

      // 2. Direct message sent by me (sender_id: 1) -> title must NOT be overwritten with my name
      viewModel.handleNewMessageForTest({
        'id': 102,
        'conversation_id': 'conv-direct-self',
        'conversation_type': 'direct',
        'content': 'Sent to someone',
        'sender_id': 1,
        'sender_name': 'My Own Name',
        'created_at': DateTime.now().toIso8601String(),
      });

      state = viewModel.conversationsBloc.state as SuccessState<List<Conversation>>;
      var selfConv = state.data.firstWhere((c) => c.id == 'conv-direct-self');
      expect(selfConv.title, isNot(equals('My Own Name')));

      AuthSession.clear();
      viewModel.dispose();
    });
  });
}
