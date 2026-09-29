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
    this.timeStamp,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String message;
  final DateTime sentAt;
  final String messageType;
  final bool isMine;
  final bool isSeen;
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

    return ChatMessage(
      id: json['id']?.toString() ?? '',
      senderId: senderId,
      receiverId: json['conversation_id']?.toString() ?? '',
      message: json['content'] as String? ?? '',
      sentAt: sentAtDateTime,
      messageType: json['message_type'] as String? ?? 'text',
      isMine: currentUserId != null && senderId == currentUserId,
      timeStamp: TimeStamp.fromDatePublish(sentAtMillis),
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
      if (timeStamp != null) 'time_stamp': timeStamp!.toJson(),
    };
  }
}
