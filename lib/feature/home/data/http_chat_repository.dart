import 'package:whatsapp_flutter_go/core/db/network/chat_endpoints.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/core/state/global_data_api.dart';

import '../model/chat_message.dart';
import '../model/chat_user.dart';
import '../model/conversation.dart';
import 'chat_repository.dart';
/// Conversations, message history, and users list come from the real chat backend.
class HttpChatRepository implements ChatRepository {
  const HttpChatRepository();

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
  Future<List<ChatUser>> getAllUsers() async {
    final response = await GlobalDataApi.instance.getResponse(
      url: ChatEndpoints.users(),
    );
    final list = _asMap(response)?['users'];
    if (list is! List) return const [];

    return list
        .whereType<Map>()
        .map((json) => ChatUser.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  @override
  Future<String> getOrCreateDirectConversation(int targetUserId) async {
    final response = await GlobalDataApi.instance.postResponse(
      url: ChatEndpoints.directConversation(),
      data: {'target_user_id': targetUserId},
    );
    final map = _asMap(response);
    final convId = map?['conversation_id']?.toString();
    if (convId == null || convId.isEmpty) {
      throw Exception('Failed to get conversation ID from server');
    }
    return convId;
  }

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  }) async {
    final responseMap = _asMap(
      await GlobalDataApi.instance.getResponse(
        url: ChatEndpoints.messages(conversationId),
        query: {
          'limit': limit,
          'before_id': ?beforeId,
          'since_id': ?sinceId,
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
    final rawNextSinceId = responseMap?['next_since_id'];
    final nextSinceId = rawNextSinceId is int
        ? rawNextSinceId
        : (rawNextSinceId != null
            ? int.tryParse(rawNextSinceId.toString())
            : null);

    final hasMore = responseMap?['has_more'] as bool? ?? (nextBeforeId != null);
    final nextCursorStr =
        (hasMore && nextBeforeId != null && nextBeforeId != 0 && nextBeforeId != '0')
            ? nextBeforeId.toString()
            : null;

    final watermarks = responseMap?['watermarks'];

    return CursorPaginationResponse(
      current: beforeId ?? sinceId?.toString(),
      data: messages,
      fromJsonFactory: ChatMessage.fromJson,
      toJsonFactory: (model) => model.toJson(),
      nextCursor: nextCursorStr,
      hasMore: hasMore,
      nextSinceId: nextSinceId,
      extra: {
        if (watermarks is Map) 'watermarks': watermarks,
        'next_since_id': ?nextSinceId,
        'has_more': hasMore,
      },
    );
  }

  Map<String, dynamic>? _asMap(dynamic value) => switch (value) {
    final Map<String, dynamic> value => value,
    final Map value => Map<String, dynamic>.from(value),
    _ => null,
  };
}
