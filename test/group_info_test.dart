import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_flutter_go/core/db/network/chat_endpoints.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/feature/group/bloc/group_info_bloc.dart';
import 'package:whatsapp_flutter_go/feature/group/data/group_repository.dart';
import 'package:whatsapp_flutter_go/feature/group/model/group_member.dart';
import 'package:whatsapp_flutter_go/feature/group/presentation/group_info_screen.dart';
import 'package:whatsapp_flutter_go/feature/home/data/chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_user.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/view_model/chat_view_model.dart';

import 'dart:convert';

final kTransparentImage = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  bool autoUncompress = true;
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => kTransparentImage.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(kTransparentImage).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class FakeGroupRepository implements GroupRepository {
  List<GroupMember> membersToReturn;
  bool shouldThrow;
  bool shouldThrowOnAdd;
  bool shouldThrowOnRemove;
  String? avatarUrlToReturn;
  int getMembersCallCount = 0;
  int addMemberCallCount = 0;
  int removeMemberCallCount = 0;
  int updateAvatarCallCount = 0;
  int? lastAddedUserId;
  int? lastRemovedUserId;
  Completer<void>? inFlightCompleter;

  FakeGroupRepository({
    this.membersToReturn = const [],
    this.shouldThrow = false,
    this.shouldThrowOnAdd = false,
    this.shouldThrowOnRemove = false,
    this.avatarUrlToReturn = 'uploads/avatars/new_group.jpg',
  });

  @override
  Future<List<GroupMember>> getGroupMembers(String conversationId) async {
    getMembersCallCount++;
    if (shouldThrow) {
      throw Exception('Failed to load group members');
    }
    return membersToReturn;
  }

  @override
  Future<String> createGroup({
    required String title,
    required List<int> memberIds,
  }) async {
    return 'conv-test-id';
  }

  @override
  Future<String> updateGroupAvatar(String conversationId, File imageFile) async {
    updateAvatarCallCount++;
    return avatarUrlToReturn ?? 'uploads/avatars/new_group.jpg';
  }

  @override
  Future<void> addGroupMember({
    required String conversationId,
    required int userId,
  }) async {
    addMemberCallCount++;
    lastAddedUserId = userId;
    if (inFlightCompleter != null) {
      await inFlightCompleter!.future;
    }
    if (shouldThrowOnAdd) {
      throw Exception('Failed to add member to group');
    }
  }

  @override
  Future<void> removeGroupMember({
    required String conversationId,
    required int userId,
  }) async {
    removeMemberCallCount++;
    lastRemovedUserId = userId;
    if (inFlightCompleter != null) {
      await inFlightCompleter!.future;
    }
    if (shouldThrowOnRemove) {
      throw Exception('Failed to remove member from group');
    }
  }
}

class FakeChatRepositoryForUsers implements ChatRepository {
  final List<ChatUser> users;
  FakeChatRepositoryForUsers(this.users);

  @override
  Future<List<ChatUser>> getAllUsers() async => users;

  @override
  Future<List<Conversation>> getConversations() async => const [];

  @override
  Future<String> getOrCreateDirectConversation(int targetUserId) async => 'direct-id';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  final testConversation = Conversation(
    id: 'f5f2a101-1111-2222-3333-444455556666',
    type: 'group',
    title: 'Flutter Devs',
    createdAt: DateTime.parse('2026-10-07T00:00:00Z'),
  );

  final testMembers = [
    GroupMember(
      id: 1,
      conversationId: 'f5f2a101-1111-2222-3333-444455556666',
      name: 'Alice Admin',
      email: 'alice@example.com',
      avatarUrl: 'uploads/avatars/alice.png',
      bio: 'Lead Developer',
      role: 'admin',
      joinedAt: DateTime.parse('2026-10-07T01:00:00Z'),
    ),
    GroupMember(
      id: 2,
      conversationId: 'f5f2a101-1111-2222-3333-444455556666',
      name: 'Bob Member',
      email: 'bob@example.com',
      avatarUrl: null,
      bio: null,
      role: 'member',
      joinedAt: DateTime.parse('2026-10-07T02:00:00Z'),
    ),
  ];

  final candidateUsers = [
    const ChatUser(id: '1', name: 'Alice Admin', avatarUrl: ''),
    const ChatUser(id: '2', name: 'Bob Member', avatarUrl: ''),
    const ChatUser(id: '3', name: 'Charlie NonMember', avatarUrl: '', bio: 'Designer'),
    const ChatUser(id: '4', name: 'Dave NonMember', avatarUrl: '', email: 'dave@test.com'),
  ];

  group('Step 4B & 4C: Endpoints & Models Tests', () {
    test('ChatEndpoints.conversationMember returns correct path', () {
      expect(
        ChatEndpoints.conversationMember('conv-123', 456),
        'conversations/conv-123/members/456',
      );
    });

    test('ChatEndpoints.conversationMembers returns correct path', () {
      expect(
        ChatEndpoints.conversationMembers('conv-123'),
        'conversations/conv-123/members',
      );
    });

    test('Members JSON parsing - handles full backend payload', () {
      final json = {
        'conversation_id': 'f5f2a101-1111-2222-3333-444455556666',
        'user_id': 101,
        'role': 'admin',
        'joined_at': '2026-10-07T09:00:00Z',
        'name': 'Charlie',
        'email': 'charlie@example.com',
        'avatar_url': 'uploads/avatars/charlie.png',
        'bio': 'Flutter enthusiast',
      };

      final member = GroupMember.fromJson(json);

      expect(member.id, 101);
      expect(member.userId, 101);
      expect(member.conversationId, 'f5f2a101-1111-2222-3333-444455556666');
      expect(member.name, 'Charlie');
      expect(member.email, 'charlie@example.com');
      expect(member.avatarUrl, 'uploads/avatars/charlie.png');
      expect(member.bio, 'Flutter enthusiast');
      expect(member.role, 'admin');
      expect(member.isAdmin, isTrue);
      expect(member.joinedAt, DateTime.parse('2026-10-07T09:00:00Z'));

      final serialized = member.toJson();
      expect(serialized['user_id'], 101);
      expect(serialized['name'], 'Charlie');
      expect(serialized['role'], 'admin');
    });

    test('Members JSON parsing - handles role=member and nulls', () {
      final json = {
        'id': 202,
        'name': 'Dave',
        'email': 'dave@example.com',
        'role': 'member',
      };

      final member = GroupMember.fromJson(json);

      expect(member.id, 202);
      expect(member.name, 'Dave');
      expect(member.avatarUrl, isNull);
      expect(member.bio, isNull);
      expect(member.role, 'member');
      expect(member.isAdmin, isFalse);
    });
  });

  group('Step 4C: Repository Tests', () {
    test('1. addGroupMember success calls repository', () async {
      final repo = FakeGroupRepository();
      await repo.addGroupMember(conversationId: 'conv-123', userId: 99);
      expect(repo.addMemberCallCount, 1);
      expect(repo.lastAddedUserId, 99);
    });

    test('2. addGroupMember error throws exception', () async {
      final repo = FakeGroupRepository(shouldThrowOnAdd: true);
      expect(
        () => repo.addGroupMember(conversationId: 'conv-123', userId: 99),
        throwsA(isA<Exception>()),
      );
    });

    test('3. removeGroupMember success calls repository', () async {
      final repo = FakeGroupRepository();
      await repo.removeGroupMember(conversationId: 'conv-123', userId: 99);
      expect(repo.removeMemberCallCount, 1);
      expect(repo.lastRemovedUserId, 99);
    });

    test('4. removeGroupMember error throws exception', () async {
      final repo = FakeGroupRepository(shouldThrowOnRemove: true);
      expect(
        () => repo.removeGroupMember(conversationId: 'conv-123', userId: 99),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Step 4B & 4C: GroupInfoBloc Tests', () {
    test('loadMembers loading -> success emits states correctly', () async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      final bloc = GroupInfoBloc(
        testConversation,
        repo: repo,
        autoLoad: false,
        currentUserIdProvider: () => 1,
      );

      expect(bloc.state, isA<InitialState>());

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<LoadingState>(),
          isA<SuccessState<GroupInfoData>>(),
        ]),
      );

      await bloc.loadMembers();
      await expectation;

      expect(bloc.state, isA<SuccessState<GroupInfoData>>());
      final stateData = (bloc.state as SuccessState<GroupInfoData>).data;
      expect(stateData.conversation.title, 'Flutter Devs');
      expect(stateData.members.length, 2);
      expect(bloc.members.length, 2);
    });

    test('loadMembers loading -> error emits ErrorState', () async {
      final repo = FakeGroupRepository(shouldThrow: true);
      final bloc = GroupInfoBloc(
        testConversation,
        repo: repo,
        autoLoad: false,
        currentUserIdProvider: () => 1,
      );

      expect(bloc.state, isA<InitialState>());

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<LoadingState>(),
          isA<ErrorState>(),
        ]),
      );

      await bloc.loadMembers();
      await expectation;

      expect(bloc.state, isA<ErrorState>());
      expect(bloc.members, isEmpty);
    });

    test('uploadGroupAvatar updates avatar and retains members', () async {
      final repo = FakeGroupRepository(
        membersToReturn: testMembers,
        avatarUrlToReturn: 'uploads/avatars/updated.png',
      );
      final bloc = GroupInfoBloc(
        testConversation,
        repo: repo,
        autoLoad: false,
        currentUserIdProvider: () => 1,
      );

      await bloc.loadMembers();
      expect(bloc.members.length, 2);

      await bloc.uploadGroupAvatar(File('mock/path/image.jpg'));

      expect(bloc.state, isA<SuccessState<GroupInfoData>>());
      final updatedData = (bloc.state as SuccessState<GroupInfoData>).data;
      expect(updatedData.conversation.avatarUrl, 'uploads/avatars/updated.png');
      expect(updatedData.members.length, 2);
    });

    test('addMember calls repo and refreshes member list from server', () async {
      final updatedList = [
        ...testMembers,
        GroupMember(
          id: 3,
          conversationId: testConversation.id,
          name: 'Charlie NonMember',
          email: 'charlie@test.com',
          role: 'member',
        ),
      ];
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      final bloc = GroupInfoBloc(
        testConversation,
        repo: repo,
        autoLoad: false,
        currentUserIdProvider: () => 1,
      );

      await bloc.loadMembers();
      expect(bloc.members.length, 2);

      repo.membersToReturn = updatedList;
      await bloc.addMember(3);

      expect(repo.addMemberCallCount, 1);
      expect(repo.lastAddedUserId, 3);
      expect(bloc.members.length, 3);
      expect(bloc.members.last.name, 'Charlie NonMember');
    });

    test('removeMember calls repo and refreshes member list from server', () async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      final bloc = GroupInfoBloc(
        testConversation,
        repo: repo,
        autoLoad: false,
        currentUserIdProvider: () => 1,
      );

      await bloc.loadMembers();
      expect(bloc.members.length, 2);

      repo.membersToReturn = [testMembers.first];
      await bloc.removeMember(2);

      expect(repo.removeMemberCallCount, 1);
      expect(repo.lastRemovedUserId, 2);
      expect(bloc.members.length, 1);
      expect(bloc.members.first.id, 1);
    });

    test('leaveGroup calls removeGroupMember for currentUserId', () async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      final bloc = GroupInfoBloc(
        testConversation,
        repo: repo,
        autoLoad: false,
        currentUserIdProvider: () => 2,
      );

      await bloc.loadMembers();
      await bloc.leaveGroup();

      expect(repo.removeMemberCallCount, 1);
      expect(repo.lastRemovedUserId, 2);
    });

    test('duplicate action is prevented while in flight', () async {
      final completer = Completer<void>();
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      repo.inFlightCompleter = completer;

      final bloc = GroupInfoBloc(
        testConversation,
        repo: repo,
        autoLoad: false,
        currentUserIdProvider: () => 1,
      );
      await bloc.loadMembers();

      final firstCall = bloc.addMember(3);
      final secondCall = bloc.addMember(4); // should be ignored

      completer.complete();
      await firstCall;
      await secondCall;

      expect(repo.addMemberCallCount, 1);
      expect(repo.lastAddedUserId, 3);
    });

    test('isOnlyAdmin is true for sole admin and leaveGroup throws', () async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      final bloc = GroupInfoBloc(
        testConversation,
        repo: repo,
        autoLoad: false,
        currentUserIdProvider: () => 1,
      );
      await bloc.loadMembers();

      expect(bloc.isCurrentMemberAdmin, isTrue);
      expect(bloc.adminCount, 1);
      expect(bloc.isOnlyAdmin, isTrue);
      expect(bloc.canLeaveGroup, isFalse);
      expect(() => bloc.leaveGroup(), throwsA(isA<Exception>()));
    });

    test('Admin can leave group when another admin exists', () async {
      final multiAdminMembers = [
        ...testMembers,
        GroupMember(
          id: 3,
          conversationId: 'conv-123',
          name: 'Charlie',
          email: 'charlie@test.com',
          role: 'admin',
          joinedAt: DateTime.now(),
        ),
      ];
      final repo = FakeGroupRepository(membersToReturn: multiAdminMembers);
      final bloc = GroupInfoBloc(
        testConversation,
        repo: repo,
        autoLoad: false,
        currentUserIdProvider: () => 1,
      );
      await bloc.loadMembers();

      expect(bloc.adminCount, 2);
      expect(bloc.isOnlyAdmin, isFalse);
      expect(bloc.canLeaveGroup, isTrue);
      await bloc.leaveGroup();
      expect(repo.removeMemberCallCount, 1);
      expect(repo.lastRemovedUserId, 1);
    });

    test('Normal member can leave group', () async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      final bloc = GroupInfoBloc(
        testConversation,
        repo: repo,
        autoLoad: false,
        currentUserIdProvider: () => 2,
      );
      await bloc.loadMembers();

      expect(bloc.isCurrentMemberAdmin, isFalse);
      expect(bloc.isOnlyAdmin, isFalse);
      expect(bloc.canLeaveGroup, isTrue);
      await bloc.leaveGroup();
      expect(repo.removeMemberCallCount, 1);
      expect(repo.lastRemovedUserId, 2);
    });
  });

  group('Step 4C: Permission / UI Matrix Tests', () {
    testWidgets('5. Admin sees Add Member and avatar camera button', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 1, // Alice is admin
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_member_button')), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    });

    testWidgets('6. Normal member does not see Add Member or avatar camera button', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 2, // Bob is normal member
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_member_button')), findsNothing);
      expect(find.byIcon(Icons.camera_alt), findsNothing);
    });

    testWidgets('7. Admin sees Remove for other members but not for themselves', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 1, // Alice (admin, id 1)
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      // Alice should not see remove for herself
      expect(find.byKey(const Key('remove_member_1')), findsNothing);
      // Alice sees remove for Bob (id 2)
      expect(find.byKey(const Key('remove_member_2')), findsOneWidget);
    });

    testWidgets('8. Normal member does not see Remove for other members', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 2, // Bob (member, id 2)
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remove_member_1')), findsNothing);
      expect(find.byKey(const Key('remove_member_2')), findsNothing);
    });

    testWidgets('9. Both admin and normal member can see Leave Group', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      // As Admin
      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leave_group_button')), findsOneWidget);

      // As Normal Member
      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leave_group_button')), findsOneWidget);
    });
  });

  group('Step 4C: Add Member Flow Tests', () {
    testWidgets('10 & 11. Add Member sheet filters out existing members and confirms non-member', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      final chatRepo = FakeChatRepositoryForUsers(candidateUsers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            chatRepository: chatRepo,
            currentUserIdProvider: () => 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Add Member
      await tester.tap(find.byKey(const Key('add_member_button')));
      await tester.pumpAndSettle();

      // Alice (id 1) and Bob (id 2) already members -> should NOT be offered
      expect(find.text('Charlie NonMember'), findsOneWidget);
      expect(find.text('Dave NonMember'), findsOneWidget);

      // Tap Charlie
      await tester.tap(find.text('Charlie NonMember'));
      await tester.pumpAndSettle();

      // Confirm dialog appears
      expect(find.text('Add Member?'), findsOneWidget);
      expect(find.text('Add "Charlie NonMember" to this group?'), findsOneWidget);

      // Confirm
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(repo.addMemberCallCount, 1);
      expect(repo.lastAddedUserId, 3);
    });

    testWidgets('Cancelled add member does not call API', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      final chatRepo = FakeChatRepositoryForUsers(candidateUsers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            chatRepository: chatRepo,
            currentUserIdProvider: () => 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_member_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Charlie NonMember'));
      await tester.pumpAndSettle();

      // Cancel dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.addMemberCallCount, 0);
    });

    testWidgets('12. Successful add refreshes member list', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      final chatRepo = FakeChatRepositoryForUsers(candidateUsers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            chatRepository: chatRepo,
            currentUserIdProvider: () => 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 members'), findsOneWidget);

      // Update repo to return 3 members on next fetch
      repo.membersToReturn = [
        ...testMembers,
        GroupMember(
          id: 3,
          conversationId: testConversation.id,
          name: 'Charlie NonMember',
          email: 'charlie@test.com',
          role: 'member',
        ),
      ];

      await tester.tap(find.byKey(const Key('add_member_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Charlie NonMember'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('3 members'), findsOneWidget);
      expect(find.text('Charlie NonMember'), findsOneWidget);
    });
  });

  group('Step 4C: Remove Member Flow Tests', () {
    testWidgets('14. Admin confirmation -> API -> member list refresh', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Remove Bob
      await tester.tap(find.byKey(const Key('remove_member_2')));
      await tester.pumpAndSettle();

      expect(find.text('Remove Member?'), findsOneWidget);
      expect(find.text('Remove "Bob Member" from this group?'), findsOneWidget);

      repo.membersToReturn = [testMembers.first];

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(repo.removeMemberCallCount, 1);
      expect(repo.lastRemovedUserId, 2);
      expect(find.text('1 members'), findsOneWidget);
      expect(find.text('Bob Member'), findsNothing);
    });

    testWidgets('15. Cancelled removal does not call API', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remove_member_2')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.removeMemberCallCount, 0);
      expect(find.text('Bob Member'), findsOneWidget);
    });

    testWidgets('16. Normal member cannot trigger another member removal', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 2, // Bob
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
    });
  });

  group('Step 4C: Leave Group Flow Tests', () {
    testWidgets('17. Confirmation -> API call', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('leave_group_button')));
      await tester.pumpAndSettle();

      expect(find.text('Leave Group?'), findsOneWidget);
      expect(find.text('Are you sure you want to leave this group?'), findsOneWidget);

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(repo.removeMemberCallCount, 1);
      expect(repo.lastRemovedUserId, 2);
    });

    testWidgets('18. Cancelled leave does not call API', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('leave_group_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.removeMemberCallCount, 0);
    });

    testWidgets('19. Successful leave removes conversation from ChatViewModel list', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);
      final viewModel = ChatViewModel(repository: FakeChatRepositoryForUsers([]));
      await tester.pump();
      viewModel.conversationsBloc.emitSuccess([testConversation]);

      expect(viewModel.conversationsBloc.state, isA<SuccessState<List<Conversation>>>());
      expect((viewModel.conversationsBloc.state as SuccessState<List<Conversation>>).data.length, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            chatViewModel: viewModel,
            currentUserIdProvider: () => 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('leave_group_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(repo.removeMemberCallCount, 1);
      final currentList = (viewModel.conversationsBloc.state as SuccessState<List<Conversation>>).data;
      expect(currentList.any((c) => c.id == testConversation.id), isFalse);
    });

    testWidgets('20. Failed leave keeps user on screen and shows error SnackBar', (tester) async {
      final repo = FakeGroupRepository(
        membersToReturn: testMembers,
        shouldThrowOnRemove: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('leave_group_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      // Screen remains visible
      expect(find.text('Flutter Devs'), findsOneWidget);
      expect(find.byKey(const Key('leave_group_button')), findsOneWidget);
      // SnackBar shown
      expect(find.textContaining('Failed to leave group'), findsOneWidget);
    });

    testWidgets('21. Only admin tapping Leave Group displays SnackBar and does NOT call repository', (tester) async {
      final repo = FakeGroupRepository(membersToReturn: testMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('leave_group_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leave_group_button')));
      await tester.pumpAndSettle();

      expect(find.text('Leave Group?'), findsNothing);
      expect(find.text('Cannot leave group as the only admin'), findsOneWidget);
      expect(repo.removeMemberCallCount, 0);
    });

    testWidgets('22. Admin leaves when another admin exists -> dialog confirmed -> API called', (tester) async {
      final multiAdminMembers = [
        ...testMembers,
        GroupMember(
          id: 3,
          conversationId: 'conv-123',
          name: 'Charlie',
          email: 'charlie@test.com',
          role: 'admin',
          joinedAt: DateTime.now(),
        ),
      ];
      final repo = FakeGroupRepository(membersToReturn: multiAdminMembers);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(
            conversation: testConversation,
            repository: repo,
            currentUserIdProvider: () => 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('leave_group_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leave_group_button')));
      await tester.pumpAndSettle();

      expect(find.text('Leave Group?'), findsOneWidget);
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(repo.removeMemberCallCount, 1);
      expect(repo.lastRemovedUserId, 1);
    });
  });
}
