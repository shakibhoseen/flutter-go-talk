import '../../../../core/model/base_model.dart';

/// Represents a persistent pending outgoing message waiting to be delivered or acknowledged.
class PendingOutboxMessage extends BaseModel {
  final String clientMessageId;
  final String conversationId;
  final String content;
  final String messageType;
  final DateTime createdAt;
  final String senderId;

  const PendingOutboxMessage({
    required this.clientMessageId,
    required this.conversationId,
    required this.content,
    this.messageType = 'text',
    required this.createdAt,
    this.senderId = '',
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'client_message_id': clientMessageId,
      'conversation_id': conversationId,
      'content': content,
      'message_type': messageType,
      'created_at': createdAt.toIso8601String(),
      if (senderId.isNotEmpty) 'sender_id': senderId,
    };
  }

  factory PendingOutboxMessage.fromJson(Map<String, dynamic> json) {
    return PendingOutboxMessage(
      clientMessageId: json['client_message_id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'text',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      senderId: json['sender_id'] as String? ?? '',
    );
  }
}
