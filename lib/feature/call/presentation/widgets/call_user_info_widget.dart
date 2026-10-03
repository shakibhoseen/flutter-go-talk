import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../data/model/call_status.dart';

class CallUserInfoWidget extends StatelessWidget {
  final String userName;
  final String avatarUrl;
  final CallStatus status;
  final int durationSeconds;
  final bool isVideo;

  const CallUserInfoWidget({
    super.key,
    required this.userName,
    required this.avatarUrl,
    required this.status,
    required this.durationSeconds,
    required this.isVideo,
  });

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getStatusText() {
    switch (status) {
      case CallStatus.calling:
        return 'Calling...';
      case CallStatus.ringing:
        return 'Ringing...';
      case CallStatus.connected:
        return _formatDuration(durationSeconds);
      case CallStatus.ended:
        return 'Call ended';
      case CallStatus.idle:
        return 'Connecting...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isVideo || status != CallStatus.connected) ...[
          CircleAvatar(
            radius: 54,
            backgroundColor: Colors.grey.shade700,
            backgroundImage: avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null,
            child: avatarUrl.isEmpty
                ? const Icon(Icons.person, size: 54, color: Colors.white70)
                : null,
          ),
          const SizedBox(height: 20),
        ],
        Text(
          userName,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _getStatusText(),
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white70,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      ],
    );
  }
}
