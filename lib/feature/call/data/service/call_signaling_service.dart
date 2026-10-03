import 'dart:async';
import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/feature/home/data/socket_event.dart';
import '../model/call_signal.dart';

class CallSignalingService {
  CallSignalingService._();
  static final CallSignalingService instance = CallSignalingService._();

  final _signalStreamController = StreamController<CallSignal>.broadcast();
  StreamSubscription<dynamic>? _socketSubscription;

  Stream<CallSignal> get signals => _signalStreamController.stream;

  void init() {
    _socketSubscription ??= ChatSocketService.instance.messages.listen(_handleSocketMessage);
  }

  void _handleSocketMessage(dynamic raw) {
    final event = decodeSocketEvent(raw);
    if (event == null) return;

    final type = event['type'] as String?;
    final payload = event['payload'];
    if (payload is! Map) return;

    if (type == 'call_offer' ||
        type == 'call_answer' ||
        type == 'ice_candidate' ||
        type == 'call_end') {
      final signal = CallSignal.fromJson(Map<String, dynamic>.from(payload), type!);
      _signalStreamController.add(signal);
    }
  }

  void sendOffer({
    required int targetUserId,
    required Map<String, dynamic> sdp,
    required bool isVideo,
  }) {
    ChatSocketService.instance.sendRaw({
      'type': 'call_offer',
      'payload': {
        'target_user_id': targetUserId,
        'signal_data': sdp,
        'is_video': isVideo,
      },
    });
  }

  void sendAnswer({
    required int targetUserId,
    required Map<String, dynamic> sdp,
    required bool isVideo,
  }) {
    ChatSocketService.instance.sendRaw({
      'type': 'call_answer',
      'payload': {
        'target_user_id': targetUserId,
        'signal_data': sdp,
        'is_video': isVideo,
      },
    });
  }

  void sendIceCandidate({
    required int targetUserId,
    required Map<String, dynamic> candidate,
  }) {
    ChatSocketService.instance.sendRaw({
      'type': 'ice_candidate',
      'payload': {
        'target_user_id': targetUserId,
        'signal_data': candidate,
        'is_video': false,
      },
    });
  }

  void sendEndCall({required int targetUserId}) {
    ChatSocketService.instance.sendRaw({
      'type': 'call_end',
      'payload': {
        'target_user_id': targetUserId,
        'signal_data': {},
        'is_video': false,
      },
    });
  }

  void dispose() {
    _socketSubscription?.cancel();
    _socketSubscription = null;
  }
}
