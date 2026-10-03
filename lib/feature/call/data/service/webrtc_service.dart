import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };

  static const Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  Future<void> initRenderers({
    required RTCVideoRenderer localRenderer,
    required RTCVideoRenderer remoteRenderer,
  }) async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<MediaStream> openUserMedia({
    required bool isVideo,
    required RTCVideoRenderer localRenderer,
  }) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': isVideo
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };

    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localStream = stream;
    localRenderer.srcObject = _localStream;
    return stream;
  }

  Future<RTCPeerConnection> createPeerConnectionInstance({
    required Function(RTCIceCandidate candidate) onIceCandidate,
    required Function(MediaStream stream) onAddRemoteStream,
    required Function(RTCPeerConnectionState state) onConnectionStateChange,
  }) async {
    final pc = await createPeerConnection(_iceServers, _config);
    _peerConnection = pc;

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        onIceCandidate(candidate);
      }
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onAddRemoteStream(_remoteStream!);
      }
    };

    pc.onConnectionState = (state) {
      onConnectionStateChange(state);
    };

    return pc;
  }

  Future<RTCSessionDescription> createOffer() async {
    if (_peerConnection == null) throw Exception('PeerConnection is null');
    final description = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peerConnection!.setLocalDescription(description);
    return description;
  }

  Future<RTCSessionDescription> createAnswer() async {
    if (_peerConnection == null) throw Exception('PeerConnection is null');
    final description = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peerConnection!.setLocalDescription(description);
    return description;
  }

  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (_peerConnection == null) throw Exception('PeerConnection is null');
    await _peerConnection!.setRemoteDescription(description);
  }

  Future<void> addCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null) return;
    await _peerConnection!.addCandidate(candidate);
  }

  void toggleAudio(bool isMuted) {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !isMuted;
    }
  }

  void toggleVideo(bool isVideoOff) {
    if (_localStream == null) return;
    for (final track in _localStream!.getVideoTracks()) {
      track.enabled = !isVideoOff;
    }
  }

  Future<void> switchCamera() async {
    if (_localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
    }
  }

  Future<void> dispose({
    RTCVideoRenderer? localRenderer,
    RTCVideoRenderer? remoteRenderer,
  }) async {
    try {
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          track.stop();
        }
        await _localStream?.dispose();
        _localStream = null;
      }
      if (_remoteStream != null) {
        for (final track in _remoteStream!.getTracks()) {
          track.stop();
        }
        await _remoteStream?.dispose();
        _remoteStream = null;
      }
      await _peerConnection?.close();
      _peerConnection = null;

      localRenderer?.srcObject = null;
      remoteRenderer?.srcObject = null;
      await localRenderer?.dispose();
      await remoteRenderer?.dispose();
    } catch (_) {}
  }
}
