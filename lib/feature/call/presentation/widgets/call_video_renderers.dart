import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../view_model/call_view_model.dart';

class CallVideoRenderers extends StatelessWidget {
  final CallViewModel viewModel;

  const CallVideoRenderers({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    if (!viewModel.isVideo) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Remote video (full screen background)
        Positioned.fill(
          child: viewModel.remoteRenderer.srcObject != null
              ? RTCVideoView(
                  viewModel.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : Container(
                  color: Colors.blueGrey.shade900,
                  child: const Center(
                    child: Text(
                      'Connecting video...',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),
                ),
        ),

        // Local video preview (Picture-in-Picture at top right corner)
        if (!viewModel.isVideoOff)
          Positioned(
            top: 50,
            right: 20,
            width: 110,
            height: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 2),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black54,
                ),
                child: RTCVideoView(
                  viewModel.localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
