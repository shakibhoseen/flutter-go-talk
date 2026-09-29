import '../../../core/state/cursor/cursor_pagination_response.dart';
import '../model/chat_message.dart';
import '../model/chat_user.dart';
import '../model/conversation.dart';

abstract class ChatRepository {
  /// The "Chat" tab — existing conversations, newest activity first.
  Future<List<Conversation>> getConversations();

  /// Every user on the app — the "Users" tab, to start a new chat.
  Future<List<ChatUser>> getAllUsers();

  /// A page of a conversation's history, oldest-first within the page.
  /// [beforeId] scrolls further back — the oldest message id already
  /// loaded, so the server returns the [limit] messages just before it.
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
  });
}
