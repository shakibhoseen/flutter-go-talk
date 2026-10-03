import 'package:flutter/material.dart';
import '../view_model/call_view_model.dart';

class CallActionButtons extends StatelessWidget {
  final CallViewModel viewModel;
  final VoidCallback onEndCall;

  const CallActionButtons({
    super.key,
    required this.viewModel,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute / Unmute
          IconButton(
            onPressed: viewModel.toggleMute,
            iconSize: 32,
            icon: Icon(
              viewModel.isMuted ? Icons.mic_off : Icons.mic,
              color: viewModel.isMuted ? Colors.redAccent : Colors.white,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white24,
              padding: const EdgeInsets.all(14),
            ),
          ),

          // Speaker Toggle (for audio call) or Switch Camera (for video call)
          if (viewModel.isVideo)
            IconButton(
              onPressed: viewModel.switchCamera,
              iconSize: 32,
              icon: const Icon(Icons.switch_camera, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white24,
                padding: const EdgeInsets.all(14),
              ),
            )
          else
            IconButton(
              onPressed: viewModel.toggleSpeaker,
              iconSize: 32,
              icon: Icon(
                viewModel.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                color: viewModel.isSpeakerOn ? Colors.greenAccent : Colors.white,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white24,
                padding: const EdgeInsets.all(14),
              ),
            ),

          // Video On / Off toggle (only visible in video calls)
          if (viewModel.isVideo)
            IconButton(
              onPressed: viewModel.toggleVideo,
              iconSize: 32,
              icon: Icon(
                viewModel.isVideoOff ? Icons.videocam_off : Icons.videocam,
                color: viewModel.isVideoOff ? Colors.redAccent : Colors.white,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white24,
                padding: const EdgeInsets.all(14),
              ),
            ),

          // End Call button
          IconButton(
            onPressed: onEndCall,
            iconSize: 36,
            icon: const Icon(Icons.call_end, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }
}
