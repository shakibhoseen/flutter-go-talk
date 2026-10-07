import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_flutter_go/core/db/network/chat_endpoints.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/chat_routes.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/feature/home/data/chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_user.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/user_page.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/view_model/chat_view_model.dart';

class MockUserRepository implements ChatRepository {
  List<ChatUser> usersToReturn;
  bool shouldThrow;
  bool shouldThrowDirectConv;
  String convIdToReturn;
  Completer<String>? directConvCompleter;
  int directConvCallCount = 0;
  int? lastTargetUserId;

  MockUserRepository({
    this.usersToReturn = const [],
    this.shouldThrow = false,
    this.shouldThrowDirectConv = false,
    this.convIdToReturn = 'conv-test-123',
    this.directConvCompleter,
  });

  @override
  Future<List<ChatUser>> getAllUsers() async {
    if (shouldThrow) {
      throw Exception('Failed to load users from backend');
    }
    return usersToReturn;
  }

  @override
  Future<String> getOrCreateDirectConversation(int targetUserId) async {
    directConvCallCount++;
    lastTargetUserId = targetUserId;
    if (shouldThrowDirectConv) {
      throw Exception('Failed to create direct conversation');
    }
    if (directConvCompleter != null) {
      return directConvCompleter!.future;
    }
    return convIdToReturn;
  }

  @override
  Future<List<Conversation>> getConversations() async => const [];

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

  group('User Discovery & ChatUser Tests', () {
    test('ChatUser.fromJson correctly parses backend contract', () {
      final json = {
        'id': 42,
        'name': 'Bob Builder',
        'email': 'bob@builder.com',
        'avatar_url': '/uploads/profiles/bob.png',
        'bio': 'Can we fix it? Yes we can!',
        'created_at': '2026-10-07T10:00:00.000Z',
      };

      final user = ChatUser.fromJson(json);

      expect(user.id, equals('42'));
      expect(user.name, equals('Bob Builder'));
      expect(user.email, equals('bob@builder.com'));
      expect(user.avatarUrl, equals('/uploads/profiles/bob.png'));
      expect(user.bio, equals('Can we fix it? Yes we can!'));
      expect(user.createdAt, equals(DateTime.utc(2026, 10, 7, 10, 0, 0)));
    });

    test('ChatUser.fromJson handles null bio and avatar_url gracefully', () {
      final json = {
        'id': 99,
        'name': 'Alice Wonder',
        'email': 'alice@wonder.com',
        'avatar_url': null,
        'bio': null,
      };

      final user = ChatUser.fromJson(json);

      expect(user.id, equals('99'));
      expect(user.name, equals('Alice Wonder'));
      expect(user.email, equals('alice@wonder.com'));
      expect(user.avatarUrl, isEmpty);
      expect(user.bio, isNull);
    });

    test('ChatUser parses backend JSON array as expected by HttpChatRepository', () {
      final rawResponse = {
        'users': [
          {
            'id': 1,
            'name': 'User One',
            'email': 'u1@test.com',
            'avatar_url': null,
            'bio': 'Bio 1',
          },
          {
            'id': 2,
            'name': 'User Two',
            'email': 'u2@test.com',
            'avatar_url': '/img2.png',
            'bio': null,
          },
        ]
      };

      final list = rawResponse['users'] as List;
      final parsed = list
          .whereType<Map<String, dynamic>>()
          .map((j) => ChatUser.fromJson(j))
          .toList();

      expect(parsed.length, equals(2));
      expect(parsed[0].id, equals('1'));
      expect(parsed[0].name, equals('User One'));
      expect(parsed[0].bio, equals('Bio 1'));
      expect(parsed[1].id, equals('2'));
      expect(parsed[1].avatarUrl, equals('/img2.png'));
    });

    testWidgets('UserPage displays real users from allUsersBloc', (tester) async {
      final repo = MockUserRepository(
        usersToReturn: [
          const ChatUser(
            id: '10',
            name: 'Sarah Connor',
            email: 'sarah@resistance.org',
            avatarUrl: '',
            bio: 'No fate but what we make',
          ),
          const ChatUser(
            id: '11',
            name: 'John Connor',
            email: 'john@resistance.org',
            avatarUrl: '',
          ),
        ],
      );

      final viewModel = ChatViewModel(repository: repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserPage(viewModel: viewModel),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Users rendered
      expect(find.text('Sarah Connor'), findsOneWidget);
      expect(find.text('No fate but what we make'), findsOneWidget);
      expect(find.text('John Connor'), findsOneWidget);
      expect(find.text('john@resistance.org'), findsOneWidget);

      viewModel.dispose();
    });

    testWidgets('UserPage displays empty state when no users are returned', (tester) async {
      final repo = MockUserRepository(usersToReturn: const []);
      final viewModel = ChatViewModel(repository: repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserPage(viewModel: viewModel),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No users found'), findsOneWidget);

      viewModel.dispose();
    });

    testWidgets('UserPage displays error state and retry button on failure', (tester) async {
      final repo = MockUserRepository(shouldThrow: true);
      final viewModel = ChatViewModel(repository: repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserPage(viewModel: viewModel),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);

      // Now fix repo and tap retry
      repo.shouldThrow = false;
      repo.usersToReturn = [
        const ChatUser(
          id: '20',
          name: 'Kyle Reese',
          avatarUrl: '',
        ),
      ];

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Kyle Reese'), findsOneWidget);

      viewModel.dispose();
    });
  });

  group('Step 2: Start/Get 1-to-1 Direct Conversation Tests', () {
    test('ChatEndpoints.directConversation returns correct endpoint path', () {
      expect(ChatEndpoints.directConversation(), equals('conversations/direct'));
    });

    testWidgets('Tapping user calls getOrCreateDirectConversation and navigates to ChatRoutes.inbox', (tester) async {
      final repo = MockUserRepository(
        convIdToReturn: 'conv-uuid-555',
        usersToReturn: [
          const ChatUser(
            id: '42',
            name: 'Arthur Dent',
            email: 'arthur@earth.galaxy',
            avatarUrl: 'https://example.com/dent.png',
          ),
        ],
      );
      final viewModel = ChatViewModel(repository: repo);
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
                builder: (_) => const Scaffold(body: Text('ChatInboxScreenView')),
              );
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => Scaffold(body: UserPage(viewModel: viewModel)),
            );
          },
          home: Scaffold(body: UserPage(viewModel: viewModel)),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on Arthur Dent
      await tester.tap(find.text('Arthur Dent'));
      await tester.pumpAndSettle();

      // Verify repository call
      expect(repo.directConvCallCount, equals(1));
      expect(repo.lastTargetUserId, equals(42));

      // Verify navigation to inbox with constructed Conversation model
      expect(find.text('ChatInboxScreenView'), findsOneWidget);
      expect(receivedConversation, isNotNull);
      expect(receivedConversation!.id, equals('conv-uuid-555'));
      expect(receivedConversation!.title, equals('Arthur Dent'));
      expect(receivedConversation!.type, equals('direct'));
      expect(receivedConversation!.otherUserId, equals(42));
      expect(receivedConversation!.avatarUrl, equals('https://example.com/dent.png'));

      viewModel.dispose();
    });

    testWidgets('Duplicate/rapid taps on user are ignored while request is in flight', (tester) async {
      final completer = Completer<String>();
      final repo = MockUserRepository(
        directConvCompleter: completer,
        usersToReturn: [
          const ChatUser(
            id: '77',
            name: 'Ford Prefect',
            email: 'ford@betelgeuse.galaxy',
            avatarUrl: '',
          ),
        ],
      );
      final viewModel = ChatViewModel(repository: repo);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          navigatorObservers: [NavigationService.observer],
          onGenerateRoute: (settings) {
            if (settings.name == ChatRoutes.inbox) {
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const Scaffold(body: Text('ChatInboxScreenView')),
              );
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => Scaffold(body: UserPage(viewModel: viewModel)),
            );
          },
          home: Scaffold(body: UserPage(viewModel: viewModel)),
        ),
      );

      await tester.pumpAndSettle();

      // Initial tap
      await tester.tap(find.text('Ford Prefect'));
      await tester.pump(); // Start async work, spinner appears

      // In-flight spinner is rendered for user
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repo.directConvCallCount, equals(1));

      // Repeated tap while still in flight
      await tester.tap(find.text('Ford Prefect'));
      await tester.pump();

      // Verify duplicate call was prevented
      expect(repo.directConvCallCount, equals(1));

      // Complete the in-flight request
      completer.complete('conv-uuid-777');
      await tester.pumpAndSettle();

      expect(find.text('ChatInboxScreenView'), findsOneWidget);

      viewModel.dispose();
    });

    testWidgets('Failure to create direct conversation displays error SnackBar with Retry', (tester) async {
      final repo = MockUserRepository(
        shouldThrowDirectConv: true,
        usersToReturn: [
          const ChatUser(
            id: '88',
            name: 'Trillian Astra',
            email: 'trillian@earth.galaxy',
            avatarUrl: '',
          ),
        ],
      );
      final viewModel = ChatViewModel(repository: repo);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          navigatorObservers: [NavigationService.observer],
          home: Scaffold(body: UserPage(viewModel: viewModel)),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Trillian
      await tester.tap(find.text('Trillian Astra'));
      await tester.pumpAndSettle();

      expect(repo.directConvCallCount, equals(1));
      // SnackBar with error message and Retry action is visible
      expect(find.textContaining('Failed to start chat'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Now resolve the failure and press Retry
      repo.shouldThrowDirectConv = false;
      repo.convIdToReturn = 'conv-uuid-888';

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(repo.directConvCallCount, equals(2));

      viewModel.dispose();
    });

    testWidgets('Non-numeric user ID displays validation SnackBar without calling repository', (tester) async {
      final repo = MockUserRepository(
        usersToReturn: [
          const ChatUser(
            id: 'invalid-non-numeric-id',
            name: 'Marvin Android',
            email: 'marvin@sirius.galaxy',
            avatarUrl: '',
          ),
        ],
      );
      final viewModel = ChatViewModel(repository: repo);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          navigatorObservers: [NavigationService.observer],
          home: Scaffold(body: UserPage(viewModel: viewModel)),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Marvin
      await tester.tap(find.text('Marvin Android'));
      await tester.pumpAndSettle();

      // Should show 'Invalid user ID' and not call repository
      expect(find.text('Invalid user ID'), findsOneWidget);
      expect(repo.directConvCallCount, equals(0));

      viewModel.dispose();
    });
  });
}
