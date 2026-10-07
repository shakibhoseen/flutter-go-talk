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
    this.avatarUrl,
    this.lastMessageId,
    this.lastMessageContent,
    this.lastMessageSenderId,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.otherUserId,
    this.isOnline = false,
    required this.createdAt,
  });

  final String id;
  final String type; // 'group' | 'direct'
  final String? title;
  final String? avatarUrl;
  final int? lastMessageId;
  final String? lastMessageContent;
  final int? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final int? otherUserId;
  final bool isOnline;
  final DateTime createdAt;

  bool get isGroup => type.toLowerCase() == 'group';

  String get displayTitle => title ?? (isGroup ? 'Group chat' : 'Direct message');

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'direct',
      title: json['title'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      lastMessageId: json['last_message_id'] is int
          ? json['last_message_id'] as int
          : int.tryParse(json['last_message_id']?.toString() ?? ''),
      lastMessageContent: json['last_message_content'] as String?,
      lastMessageSenderId: json['last_message_sender_id'] as int?,
      lastMessageAt: DateTime.tryParse(json['last_message_at'] as String? ?? ''),
      unreadCount: json['unread_count'] as int? ?? 0,
      otherUserId: json['other_user_id'] as int?,
      isOnline: json['is_online'] as bool? ?? false,
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
      'avatar_url': avatarUrl,
      'last_message_content': lastMessageContent,
      'last_message_sender_id': lastMessageSenderId,
      'last_message_at': lastMessageAt?.toIso8601String(),
      'unread_count': unreadCount,
      'other_user_id': otherUserId,
      'is_online': isOnline,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Applies a `new_message` socket event's preview fields, keeping
  /// everything else (id, type, title, unread count) as-is.
  Conversation copyWith({
    String? id,
    String? type,
    String? title,
    String? avatarUrl,
    int? lastMessageId,
    String? lastMessageContent,
    int? lastMessageSenderId,
    DateTime? lastMessageAt,
    int? unreadCount,
    int? otherUserId,
    bool? isOnline,
    DateTime? createdAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessageContent: lastMessageContent ?? this.lastMessageContent,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      otherUserId: otherUserId ?? this.otherUserId,
      isOnline: isOnline ?? this.isOnline,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Conversation copyWithNewMessage({
    int? messageId,
    String? content,
    int? senderId,
    DateTime? at,
  }) {
    return Conversation(
      id: id,
      type: type,
      title: title,
      avatarUrl: avatarUrl,
      lastMessageId: messageId ?? lastMessageId,
      lastMessageContent: content ?? lastMessageContent,
      lastMessageSenderId: senderId ?? lastMessageSenderId,
      lastMessageAt: at ?? lastMessageAt,
      unreadCount: unreadCount,
      otherUserId: otherUserId,
      createdAt: createdAt,
    );
  }
}
