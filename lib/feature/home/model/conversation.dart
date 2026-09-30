import '../../../core/model/base_model.dart';

/// Matches the backend's `GET /conversations` shape exactly — a `direct`
/// conversation carries no `title` (there's no "other user" field in this
/// list endpoint either), so [displayTitle] is the one fallback point for
/// that gap.
class Conversation extends BaseModel {
  const Conversation({
    required this.id,
    required this.type,
    this.title,
    this.lastMessageContent,
    this.lastMessageSenderId,
    this.lastMessageAt,
    this.unreadCount = 0,
    required this.createdAt,
  });

  final String id;
  final String type; // 'group' | 'direct'
  final String? title;
  final String? lastMessageContent;
  final int? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;

  bool get isGroup => type.toLowerCase() == 'group';

  String get displayTitle => title ?? (isGroup ? 'Group chat' : 'Direct message');

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'direct',
      title: json['title'] as String?,
      lastMessageContent: json['last_message_content'] as String?,
      lastMessageSenderId: json['last_message_sender_id'] as int?,
      lastMessageAt: DateTime.tryParse(json['last_message_at'] as String? ?? ''),
      unreadCount: json['unread_count'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'last_message_content': lastMessageContent,
      'last_message_sender_id': lastMessageSenderId,
      'last_message_at': lastMessageAt?.toIso8601String(),
      'unread_count': unreadCount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Applies a `new_message` socket event's preview fields, keeping
  /// everything else (id, type, title, unread count) as-is.
  Conversation copyWithNewMessage({
    String? content,
    int? senderId,
    DateTime? at,
  }) {
    return Conversation(
      id: id,
      type: type,
      title: title,
      lastMessageContent: content ?? lastMessageContent,
      lastMessageSenderId: senderId ?? lastMessageSenderId,
      lastMessageAt: at ?? lastMessageAt,
      unreadCount: unreadCount,
      createdAt: createdAt,
    );
  }
}
