import '../../../core/model/base_model.dart';

class ChatUser extends BaseModel {
  const ChatUser({
    required this.id,
    required this.name,
    required this.avatarUrl,
    this.email,
    this.bio,
    this.isOnline = false,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String avatarUrl;
  final String? email;
  final String? bio;
  final bool isOnline;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime? createdAt;

  /// Whether this user has an existing conversation — the "Chat" tab shows
  /// only these, the "Users" tab shows everyone.
  bool get hasConversation => lastMessage != null;

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      email: json['email'] as String?,
      bio: json['bio'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      lastMessage: json['last_message'] as String?,
      lastMessageAt: DateTime.tryParse(json['last_message_at'] as String? ?? ''),
      unreadCount: json['unread_count'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar_url': avatarUrl,
      'email': email,
      'bio': bio,
      'is_online': isOnline,
      'last_message': lastMessage,
      'last_message_at': lastMessageAt?.toIso8601String(),
      'unread_count': unreadCount,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  ChatUser copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? email,
    String? bio,
    bool? isOnline,
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? createdAt,
  }) {
    return ChatUser(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      email: email ?? this.email,
      bio: bio ?? this.bio,
      isOnline: isOnline ?? this.isOnline,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
