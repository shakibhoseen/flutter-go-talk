/// Paths on the chat backend (see [NetworkServiceType.chat]).
final class ChatEndpoints {
  ChatEndpoints._();

  static String conversations() => 'conversations';

  static String users() => 'users';

  static String directConversation() => 'conversations/direct';

  static String groupConversation() => 'conversations/group';

  static String messages(String conversationId) =>
      'conversations/$conversationId/messages';

  static String conversationMembers(String conversationId) =>
      'conversations/$conversationId/members';

  static String conversationMember(String conversationId, int userId) =>
      'conversations/$conversationId/members/$userId';

  static String presence() => 'presence';
}
