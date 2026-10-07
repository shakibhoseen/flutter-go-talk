typedef SocketEventCallback = void Function(
    Map<String, dynamic> payload,
    );

abstract final class ChatSocketEventType {
  static const newMessage = 'new_message';
  static const statusUpdated = 'status_updated';
  static const memberReadWatermark = 'member_read_watermark';

  static const typing = 'typing';
  static const userPresence = 'user_presence';

  static const callOffer = 'call_offer';
  static const callAnswer = 'call_answer';
  static const iceCandidate = 'ice_candidate';
  static const callEnd = 'call_end';
}