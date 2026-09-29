/// Paths on the chat backend (see [NetworkServiceType.chat]).
final class ChatEndpoints {
  ChatEndpoints._();

  static String conversations() => 'conversations';

  static String messages(String conversationId) =>
      'conversations/$conversationId/messages';
}
