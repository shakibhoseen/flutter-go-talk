import '../../../core/state/cursor/cursor_pagination_response.dart';
import '../model/chat_message.dart';
import '../model/chat_user.dart';
import '../model/conversation.dart';

abstract class ChatRepository {
  /// The "Chat" tab — existing conversations, newest activity first.
  Future<List<Conversation>> getConversations();

  /// Every user on the app — the "Users" tab, to start a new chat.
  Future<List<ChatUser>> getAllUsers();

  /// Gets or creates a 1-to-1 conversation with [targetUserId].
  Future<String> getOrCreateDirectConversation(int targetUserId);

  /// A page of a conversation's history, oldest-first within the page.
  /// [beforeId] scrolls further back (history).
  /// [sinceId] fetches newer/missed messages after this id (forward delta sync).
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  });

  /// Watches conversations through persistent local cache (stale-while-revalidate).
  /// Emits cached conversations immediately if available, then refreshes from the network.
  Stream<List<Conversation>> watchConversations({
    Duration? maxStale,
    bool? invalidCache,
    Duration maxAge = const Duration(minutes: 5),
  }) =>
      Stream.fromFuture(getConversations());

  /// Persists the updated conversation list to the local cache.
  Future<void> persistConversations(List<Conversation> conversations) async {}
}
