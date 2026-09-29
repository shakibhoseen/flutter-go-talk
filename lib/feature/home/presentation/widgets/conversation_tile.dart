import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/helper/relative_time.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';

import '../../model/conversation.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primaryColor.shade100,
        child: Icon(
          conversation.isGroup ? Icons.groups : Icons.person,
          color: AppColors.primaryColor,
        ),
      ),
      title: Text(
        conversation.displayTitle,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        conversation.lastMessageContent ?? 'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: conversation.unreadCount > 0
          ? CircleAvatar(
              radius: 10,
              backgroundColor: Colors.green,
              child: Text(
                '${conversation.unreadCount}',
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            )
          : conversation.lastMessageAt != null
          ? Text(relativeTime(conversation.lastMessageAt!))
          : null,
    );
  }
}
