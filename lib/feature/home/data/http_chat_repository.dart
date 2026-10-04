import 'package:whatsapp_flutter_go/core/db/network/chat_endpoints.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/core/state/global_data_api.dart';

import '../model/chat_message.dart';
import '../model/chat_user.dart';
import '../model/conversation.dart';
import 'chat_repository.dart';
import 'fake_chat_repository.dart';

/// Conversations and message history come from the real backend now.
/// Users-to-start-a-chat-with doesn't have an endpoint yet, so that one
/// still falls back to [FakeChatRepository] — point it at a real one the
/// day it exists; nothing above this layer needs to change.
class HttpChatRepository implements ChatRepository {
  const HttpChatRepository();

  static const _fallback = FakeChatRepository();

  @override
  Future<List<Conversation>> getConversations() async {
    final response = await GlobalDataApi.instance.getResponse(
      url: ChatEndpoints.conversations(),
    );
    final list = _asMap(response)?['conversations'];
    if (list is! List) return const [];

    final conversations = list
        .whereType<Map>()
        .map((json) => Conversation.fromJson(Map<String, dynamic>.from(json)))
        .toList();

    // Don't trust the backend's own ordering — sort by recency here too, so
    // a fresh fetch always agrees with where the socket's `new_message`
    // handling would have moved a conversation to.
    conversations.sort(
      (a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(
        a.lastMessageAt ?? a.createdAt,
      ),
    );
    return conversations;
  }

  @override
  Future<List<ChatUser>> getAllUsers() => _fallback.getAllUsers();

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
  }) async {
    final responseMap = _asMap(
      await GlobalDataApi.instance.getResponse(
        url: ChatEndpoints.messages(conversationId),
        query: {
          'limit': limit,
          'before_id': ?beforeId,
        },
      ),
    );

    final list = responseMap?['messages'];
    final myId = AuthSession.tokens?.user?.id?.toString();
    final messages = list is List
        ? list
            .whereType<Map>()
            .map(
              (json) => ChatMessage.fromJson(
                Map<String, dynamic>.from(json),
                currentUserId: myId,
              ),
            )
            .toList()
        : <ChatMessage>[];

    final nextBeforeId = responseMap?['next_before_id'];
    final hasMore = responseMap?['has_more'] as bool? ?? (nextBeforeId != null);
    final nextCursorStr =
        (hasMore && nextBeforeId != null && nextBeforeId != 0 && nextBeforeId != '0')
            ? nextBeforeId.toString()
            : null;

    final watermarks = responseMap?['watermarks'];

    return CursorPaginationResponse(
      current: beforeId,
      data: messages,
      fromJsonFactory: ChatMessage.fromJson,
      toJsonFactory: (model) => model.toJson(),
      nextCursor: nextCursorStr,
      extra: {
        if (watermarks is Map) 'watermarks': watermarks,
      },
    );
  }

  Map<String, dynamic>? _asMap(dynamic value) => switch (value) {
    final Map<String, dynamic> value => value,
    final Map value => Map<String, dynamic>.from(value),
    _ => null,
  };
}
