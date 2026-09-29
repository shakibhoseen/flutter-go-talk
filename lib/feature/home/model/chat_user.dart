import '../../../core/model/base_model.dart';

class ChatUser extends BaseModel {
  const ChatUser({
    required this.id,
    required this.name,
    required this.avatarUrl,
    this.isOnline = false,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String id;
  final String name;
  final String avatarUrl;
  final bool isOnline;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// Whether this user has an existing conversation — the "Chat" tab shows
  /// only these, the "Users" tab shows everyone.
  bool get hasConversation => lastMessage != null;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar_url': avatarUrl,
      'is_online': isOnline,
      'last_message': lastMessage,
      'last_message_at': lastMessageAt?.toIso8601String(),
      'unread_count': unreadCount,
    };
  }
}
