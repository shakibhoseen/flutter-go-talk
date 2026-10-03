import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../data/model/call_signal.dart';
import '../../data/model/call_status.dart';
import '../../data/service/call_signaling_service.dart';
import '../../data/service/webrtc_service.dart';

class CallViewModel extends ChangeNotifier {
  final WebRTCService _webrtcService = WebRTCService();
  final CallSignalingService _signalingService = CallSignalingService.instance;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  CallStatus status = CallStatus.idle;
  bool isMuted = false;
  bool isVideoOff = false;
  bool isSpeakerOn = false;
  bool isVideo = false;
  int targetUserId = 0;
  int durationSeconds = 0;

  Timer? _timer;
  StreamSubscription<CallSignal>? _signalSubscription;

  Future<void> initCall({
    required int targetUserId,
    required bool isVideo,
    required bool isIncoming,
    Map<String, dynamic>? offerSdp,
  }) async {
    this.targetUserId = targetUserId;
    this.isVideo = isVideo;
    isVideoOff = !isVideo;

    _signalingService.init();
    await _webrtcService.initRenderers(
      localRenderer: localRenderer,
      remoteRenderer: remoteRenderer,
    );

    await _webrtcService.openUserMedia(
      isVideo: isVideo,
      localRenderer: localRenderer,
    );

    await _webrtcService.createPeerConnectionInstance(
      onIceCandidate: (candidate) {
        _signalingService.sendIceCandidate(
          targetUserId: targetUserId,
          candidate: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      },
      onAddRemoteStream: (stream) {
        remoteRenderer.srcObject = stream;
        notifyListeners();
      },
      onConnectionStateChange: (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          status = CallStatus.connected;
          _startTimer();
          notifyListeners();
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          endCall();
        }
      },
    );

    _listenSignaling();

    if (isIncoming && offerSdp != null) {
      status = CallStatus.connected;
      notifyListeners();
      await _handleIncomingOffer(offerSdp);
    } else {
      status = CallStatus.calling;
      notifyListeners();
      await _createAndSendOffer();
    }
  }

  void _listenSignaling() {
    _signalSubscription = _signalingService.signals.listen((signal) async {
      if (signal.fromUserId != targetUserId) return;

      if (signal.type == 'call_answer') {
        final data = signal.signalData as Map<String, dynamic>;
        final description = RTCSessionDescription(data['sdp'], data['type']);
        await _webrtcService.setRemoteDescription(description);
      } else if (signal.type == 'ice_candidate') {
        final data = signal.signalData as Map<String, dynamic>;
        final candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );
        await _webrtcService.addCandidate(candidate);
      } else if (signal.type == 'call_end') {
        endCall(notifyRemote: false);
      }
    });
  }

  Future<void> _createAndSendOffer() async {
    final offer = await _webrtcService.createOffer();
    _signalingService.sendOffer(
      targetUserId: targetUserId,
      sdp: {'sdp': offer.sdp, 'type': offer.type},
      isVideo: isVideo,
    );
  }

  Future<void> _handleIncomingOffer(Map<String, dynamic> offerSdp) async {
    final description = RTCSessionDescription(offerSdp['sdp'], offerSdp['type']);
    await _webrtcService.setRemoteDescription(description);

    final answer = await _webrtcService.createAnswer();
    _signalingService.sendAnswer(
      targetUserId: targetUserId,
      sdp: {'sdp': answer.sdp, 'type': answer.type},
      isVideo: isVideo,
    );
  }

  void _startTimer() {
    _timer?.cancel();
    durationSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      durationSeconds++;
      notifyListeners();
    });
  }

  void toggleMute() {
    isMuted = !isMuted;
    _webrtcService.toggleAudio(isMuted);
    notifyListeners();
  }

  void toggleVideo() {
    isVideoOff = !isVideoOff;
    _webrtcService.toggleVideo(isVideoOff);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    await _webrtcService.switchCamera();
  }

  void toggleSpeaker() {
    isSpeakerOn = !isSpeakerOn;
    // Helper handles speaker routing on mobile platforms
    notifyListeners();
  }

  void endCall({bool notifyRemote = true}) {
    if (status == CallStatus.ended) return;
    status = CallStatus.ended;
    _timer?.cancel();

    if (notifyRemote && targetUserId > 0) {
      _signalingService.sendEndCall(targetUserId: targetUserId);
    }

    _signalSubscription?.cancel();
    _webrtcService.dispose(
      localRenderer: localRenderer,
      remoteRenderer: remoteRenderer,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _signalSubscription?.cancel();
    _webrtcService.dispose(
      localRenderer: localRenderer,
      remoteRenderer: remoteRenderer,
    );
    super.dispose();
  }
}
