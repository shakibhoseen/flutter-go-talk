import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';

import '../model/chat_message.dart';
import '../model/chat_user.dart';
import '../model/conversation.dart';
import 'chat_repository.dart';

/// Static stand-in for the real chat API — placeholder data so `ChatPage` /
/// `UserPage` / `ChatThreadPage` can be built and ported from `hk` before the
/// Go backend has chat endpoints. Swap for a real [ChatRepository]
/// implementation later; nothing above this layer should need to change.
class FakeChatRepository implements ChatRepository {
  const FakeChatRepository();

  static final DateTime _now = DateTime.now();

  static final List<ChatUser> _users = [
    ChatUser(
      id: 'u1',
      name: 'Ayesha Rahman',
      avatarUrl: '',
      isOnline: true,
      lastMessage: 'See you tomorrow!',
      lastMessageAt: _now.subtract(const Duration(minutes: 5)),
      unreadCount: 2,
    ),
    ChatUser(
      id: 'u2',
      name: 'Tanvir Hasan',
      avatarUrl: '',
      lastMessage: 'Ok, sounds good.',
      lastMessageAt: _now.subtract(const Duration(hours: 2)),
    ),
    ChatUser(id: 'u3', name: 'Nusrat Jahan', avatarUrl: '', isOnline: true),
    ChatUser(id: 'u4', name: 'Rafiul Islam', avatarUrl: ''),
    ChatUser(
      id: 'u5',
      name: 'Sabbir Ahmed',
      avatarUrl: '',
      isOnline: true,
      lastMessage: 'Sent the files.',
      lastMessageAt: _now.subtract(const Duration(days: 1)),
    ),
  ];

  static final Map<String, List<ChatMessage>> _messages = {
    'u1': [
      ChatMessage(
        id: 'm1',
        senderId: 'u1',
        receiverId: 'me',
        message: "Hey, are you free tonight?",
        sentAt: _now.subtract(const Duration(minutes: 20)),
      ),
      ChatMessage(
        id: 'm2',
        senderId: 'me',
        receiverId: 'u1',
        message: "Yeah, what's up?",
        sentAt: _now.subtract(const Duration(minutes: 15)),
        isMine: true,
      ),
      ChatMessage(
        id: 'm3',
        senderId: 'u1',
        receiverId: 'me',
        message: 'See you tomorrow!',
        sentAt: _now.subtract(const Duration(minutes: 5)),
      ),
    ],
    'u2': [
      ChatMessage(
        id: 'm4',
        senderId: 'me',
        receiverId: 'u2',
        message: 'Can we push the meeting?',
        sentAt: _now.subtract(const Duration(hours: 3)),
        isMine: true,
      ),
      ChatMessage(
        id: 'm5',
        senderId: 'u2',
        receiverId: 'me',
        message: 'Ok, sounds good.',
        sentAt: _now.subtract(const Duration(hours: 2)),
      ),
    ],
    'u5': [
      ChatMessage(
        id: 'm6',
        senderId: 'u5',
        receiverId: 'me',
        message: 'Sent the files.',
        sentAt: _now.subtract(const Duration(days: 1)),
      ),
    ],
  };

  @override
  Future<List<Conversation>> getConversations() async {
    await Future.delayed(const Duration(milliseconds: 300));
    final withConversation = _users.where((u) => u.hasConversation).toList()
      ..sort(
        (a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(
          a.lastMessageAt ?? DateTime(0),
        ),
      );
    return withConversation
        .map(
          (u) => Conversation(
            id: u.id,
            type: 'direct',
            title: u.name,
            lastMessageContent: u.lastMessage,
            lastMessageAt: u.lastMessageAt,
            unreadCount: u.unreadCount,
            createdAt: u.lastMessageAt ?? _now,
          ),
        )
        .toList();
  }

  @override
  Future<List<ChatUser>> getAllUsers() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_users);
  }

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // No history beyond the canned first page — pagination has nothing real
    // to page through until this repository's data does.

    var data = _messages[conversationId] ?? const [];
    if (beforeId != null) data = <ChatMessage>[];

    return CursorPaginationResponse(
      data: data,
      fromJsonFactory: ChatMessage.fromJson,
      toJsonFactory: (model) => {},
      nextCursor: 'next',
    );
  }
}
