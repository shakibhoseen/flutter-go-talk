import '../../../core/model/base_model.dart';

class GroupMember extends BaseModel {
  final int id;
  final String conversationId;
  final String name;
  final String email;
  final String? avatarUrl;
  final String? bio;
  final String role;
  final DateTime? joinedAt;

  const GroupMember({
    required this.id,
    required this.conversationId,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.bio,
    this.role = 'member',
    this.joinedAt,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';

  int get userId => id;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final rawUserId = json['user_id'] ?? json['id'];
    final userId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '') ?? 0;

    return GroupMember(
      id: userId,
      conversationId: json['conversation_id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      role: json['role'] as String? ?? 'member',
      joinedAt: DateTime.tryParse(
        json['joined_at'] as String? ?? json['created_at'] as String? ?? '',
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'user_id': id,
      'id': id,
      'conversation_id': conversationId,
      'name': name,
      'email': email,
      'avatar_url': avatarUrl,
      'bio': bio,
      'role': role,
      'joined_at': joinedAt?.toIso8601String(),
    };
  }

  GroupMember copyWith({
    int? id,
    String? conversationId,
    String? name,
    String? email,
    String? avatarUrl,
    String? bio,
    String? role,
    DateTime? joinedAt,
  }) {
    return GroupMember(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupMember &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          conversationId == other.conversationId &&
          role == other.role;

  @override
  int get hashCode => id.hashCode ^ conversationId.hashCode ^ role.hashCode;
}
