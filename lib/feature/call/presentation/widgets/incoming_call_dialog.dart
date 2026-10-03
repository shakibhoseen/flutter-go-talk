import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class IncomingCallDialog extends StatelessWidget {
  final String callerName;
  final String callerAvatar;
  final bool isVideo;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallDialog({
    super.key,
    required this.callerName,
    this.callerAvatar = '',
    required this.isVideo,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.blueGrey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey.shade700,
              backgroundImage: callerAvatar.isNotEmpty
                  ? CachedNetworkImageProvider(callerAvatar)
                  : null,
              child: callerAvatar.isEmpty
                  ? const Icon(Icons.person, size: 40, color: Colors.white70)
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              callerName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isVideo ? 'Incoming Video Call...' : 'Incoming Voice Call...',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline button
                IconButton(
                  onPressed: onDecline,
                  iconSize: 34,
                  icon: const Icon(Icons.call_end, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                // Accept button
                IconButton(
                  onPressed: onAccept,
                  iconSize: 34,
                  icon: Icon(
                    isVideo ? Icons.videocam : Icons.call,
                    color: Colors.white,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
