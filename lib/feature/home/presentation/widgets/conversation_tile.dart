import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/config/app_flavor_config.dart';
import 'package:whatsapp_flutter_go/core/db/network/network_service_type.dart';
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

  String _getFullUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final baseUrl = AppFlavorConfig.baseUrlFor(NetworkServiceType.chat);
    return '$baseUrl/$path';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryColor.shade100,
            backgroundImage: conversation.avatarUrl != null
                ? NetworkImage(_getFullUrl(conversation.avatarUrl))
                : null,
            child: conversation.avatarUrl == null
                ? Icon(
                    conversation.isGroup ? Icons.groups : Icons.person,
                    color: AppColors.primaryColor,
                  )
                : null,
          ),
          if (conversation.isGroup)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.groups,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
        ],
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
