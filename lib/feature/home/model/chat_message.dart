import '../../../core/helper/date_custom.dart';
import '../../../core/model/base_model.dart';

class TimeStamp extends BaseModel {
  final String dateCompare;
  final String hourMinute;

  TimeStamp({required this.dateCompare, required this.hourMinute});

  factory TimeStamp.fromDatePublish(int time) {
    final data = DateCustom().formatTimestampWithTime(time);
    return TimeStamp(
        dateCompare: data.dateCompare, hourMinute: data.hourMinute);
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'date_compare': dateCompare,
      'hour_minute': hourMinute,
    };
  }
}

class ChatMessage extends BaseModel {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.sentAt,
    this.messageType = 'text',
    this.isMine = false,
    this.isSeen = false,
    this.isDelivered = false,
    this.timeStamp,
    this.senderName = '',
    this.senderAvatar = '',
    this.readBy = const [],
    this.readCount = 0,
  });

  final String senderName;
  final String senderAvatar;
  final List<ReadReceiptUser> readBy;
  final int readCount;
  final String id;
  final String senderId;
  final String receiverId;
  final String message;
  final DateTime sentAt;
  final String messageType;
  final bool isMine;
  final bool isSeen;
  final bool isDelivered;
  final TimeStamp? timeStamp;

  /// [currentUserId] is passed in rather than read from session state here,
  /// so this stays a pure mapper — the repository (or whoever else parses a
  /// server/socket payload) decides who "me" is.
  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final senderId = json['sender_id']?.toString() ?? '';
    final createdAtStr = json['created_at'] as String? ?? '';
    final sentAtDateTime = DateTime.tryParse(createdAtStr) ?? DateTime.now();
    final sentAtMillis = json['sent_at'] is int
        ? json['sent_at'] as int
        : sentAtDateTime.millisecondsSinceEpoch;
    final readByList = (json['read_by'] as List<dynamic>?)
        ?.map((e) => ReadReceiptUser.fromJson(Map<String, dynamic>.from(e)))
        .toList() ??
        [];

    final readCount = json['read_count'] as int? ?? 0;

    return ChatMessage(
      id: json['id']?.toString() ?? '',
      senderId: senderId,
      receiverId: json['conversation_id']?.toString() ?? '',
      message: json['content'] as String? ?? '',
      sentAt: sentAtDateTime,
      messageType: json['message_type'] as String? ?? 'text',
      isMine: currentUserId != null && senderId == currentUserId,
      timeStamp: TimeStamp.fromDatePublish(sentAtMillis),
      senderName: json['sender_name'] as String? ?? '',
      senderAvatar: json['sender_avatar'] as String? ?? '',
      readBy: readByList,
      readCount: readCount,
      isSeen: json['is_seen'] == true || readCount > 0,
      isDelivered: json['is_delivered'] == true || json['is_seen'] == true || readCount > 0,
    );
  }

  ChatMessage copyWith({
    bool? isSeen,
    bool? isDelivered,
    List<ReadReceiptUser>? readBy,
    int? readCount,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      message: message,
      sentAt: sentAt,
      messageType: messageType,
      isMine: isMine,
      isSeen: isSeen ?? this.isSeen,
      isDelivered: isDelivered ?? this.isDelivered,
      timeStamp: timeStamp,
      senderName: senderName,
      senderAvatar: senderAvatar,
      readBy: readBy ?? this.readBy,
      readCount: readCount ?? this.readCount,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'conversation_id': receiverId,
      'content': message,
      'created_at': sentAt.toIso8601String(),
      'message_type': messageType,
      'is_seen': isSeen,
      'is_delivered': isDelivered,
      if (timeStamp != null) 'time_stamp': timeStamp!.toJson(),
    };
  }
}


class ReadReceiptUser extends BaseModel{
  final int userId;
  final String name;
  final String avatarUrl;

  const ReadReceiptUser({
    required this.userId,
    required this.name,
    required this.avatarUrl,
  });


  factory ReadReceiptUser.fromJson(Map<String, dynamic> json) {
    return ReadReceiptUser(
      userId: json['user_id'] is int
          ? json['user_id'] as int
          : int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'avatar_url': avatarUrl,
    };
  }

  ReadReceiptUser copyWith({
    int? userId,
    String? name,
    String? avatarUrl,
  }) {
    return ReadReceiptUser(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  @override
  String toString() =>
      'ReadReceiptUser(userId: $userId, name: $name, avatarUrl: $avatarUrl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ReadReceiptUser &&
              runtimeType == other.runtimeType &&
              userId == other.userId;

  @override
  int get hashCode => userId.hashCode;
}
