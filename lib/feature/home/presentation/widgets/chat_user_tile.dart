import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';

import '../../model/chat_user.dart';

class ChatUserTile extends StatelessWidget {
  const ChatUserTile({super.key, required this.user, required this.onTap});

  final ChatUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryColor.shade100,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (user.isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        user.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        user.lastMessage ?? 'Tap to start chatting',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: user.unreadCount > 0
          ? CircleAvatar(
              radius: 10,
              backgroundColor: Colors.green,
              child: Text(
                '${user.unreadCount}',
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            )
          : user.lastMessageAt != null
          ? Text(_formatTime(user.lastMessageAt!))
          : null,
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
