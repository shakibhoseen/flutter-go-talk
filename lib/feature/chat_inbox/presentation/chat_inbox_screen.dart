import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/config/app_flavor_config.dart';
import 'package:whatsapp_flutter_go/core/db/network/network_service_type.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/group/presentation/group_info_screen.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/presentation/widgets/message_design.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_sync_coordinator.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';

import '../../../core/controllers/my_scroll_controller.dart';
import '../../../core/db/network/socket/chat_socket_event_dispatcher.dart';
import '../../../core/db/network/socket/chat_socket_event_type.dart';
import '../../../core/db/network/socket/chat_socket_service.dart';
import '../../../core/session/auth_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/cute_avatar.dart';
import '../../../gen/assets.gen.dart';
import '../../home/model/conversation.dart';
import '../../call/presentation/call_screen.dart';
import '../../call/data/service/call_permission_service.dart';

class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  InboxMessageListCursorBloc? inboxBloc;
  final _controller = TextEditingController();
  Conversation? conversationArgs;
  final _socketDispatcher =
      ChatSocketEventDispatcher.instance;

  String? get _myId => AuthSession.tokens?.user?.id?.toString();
  MyCursorScrollController? cursorScrollController;
  StreamSubscription<dynamic>? _blocSubscription;
  String? _lastAckedMessageId;

  VoidCallback? _removeNewMessageListener;
  VoidCallback? _removeStatusUpdatedListener;
  VoidCallback? _removeWatermarkListener;
  VoidCallback? _removePresenceListener;
  bool _isOtherUserOnline = false;

  String _getFullUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    // We assume AppFlavorConfig is imported, but we might need to add import
    final baseUrl = AppFlavorConfig.baseUrlFor(NetworkServiceType.chat);
    return '$baseUrl/$path';
  }

  void _checkAndSendSeenAck() {
    final items = inboxBloc?.cursorPageHolder.items ?? [];
    if (items.isEmpty || conversationArgs?.id == null) return;

    ChatMessage? latestIncoming;
    for (final item in items) {
      if (!item.isMine && item.id.isNotEmpty) {
        final parsedId = int.tryParse(item.id);
        if (parsedId != null && parsedId > 0) {
          latestIncoming = item;
          break;
        }
      }
    }

    if (latestIncoming != null) {
      final incomingId = int.tryParse(latestIncoming.id) ?? 0;
      final lastAckedId = _lastAckedMessageId != null
          ? (int.tryParse(_lastAckedMessageId!) ?? 0)
          : 0;

      if (incomingId > 0 && incomingId > lastAckedId) {
        _lastAckedMessageId = latestIncoming.id;
        ChatSocketService.instance.sendSeenAck(
          conversationId: conversationArgs!.id,
          messageId: latestIncoming.id,
          senderId: int.tryParse(latestIncoming.senderId) ?? 0,
        );
      }
    }
  }

  void _resendMessage() {}

  @override
  void initState() {
    conversationArgs = NavigationService.getArguments<Conversation>();
    _isOtherUserOnline = conversationArgs?.isOnline ?? false;
    if (conversationArgs?.id != null) {
      inboxBloc = InboxMessageListCursorBloc(
        conversationId: conversationArgs!.id,
        isGroup: conversationArgs?.isGroup == true,
      );
      _blocSubscription = inboxBloc?.stream.listen((state) {
        _checkAndSendSeenAck();
        if (mounted) {
          setState(() {});
        }
      });
      inboxBloc?.execute();
      cursorScrollController = MyCursorScrollController(
        inboxBloc!,
        () {
          inboxBloc?.execute();
        },
        cursorDataHolder: inboxBloc!.cursorPageHolder,
        isReverse: true,
      );
      _listenToSocketEvents();
      _registerActiveBloc();
    }

    super.initState();
  }

  void _registerActiveBloc() {
    if (inboxBloc != null) {
      ChatSyncCoordinator.instance.registerActiveBloc(
        inboxBloc!,
        onSyncSuccess: () {
          if (mounted) {
            _checkAndSendSeenAck();
          }
        },
      );
    }
  }

  void _listenToSocketEvents() {
    final conversationId = conversationArgs?.id;

    if (conversationId == null) return;

    _removeNewMessageListener = _socketDispatcher.listen(
      eventType: ChatSocketEventType.newMessage,
      conversationId: conversationId,
      callback: _handleNewMessage,
    );

    _removeStatusUpdatedListener = _socketDispatcher.listen(
      eventType: ChatSocketEventType.statusUpdated,
      conversationId: conversationId,
      callback: _handleStatusUpdated,
    );

    _removeWatermarkListener = _socketDispatcher.listen(
      eventType: ChatSocketEventType.memberReadWatermark,
      conversationId: conversationId,
      callback: _handleMemberReadWatermark,
    );

    _removePresenceListener = _socketDispatcher.listen(
      eventType: ChatSocketEventType.userPresence,
      callback: (payload) {
        if (!mounted) return;
        final rawUserId = payload['user_id'];
        final userId = rawUserId is int ? rawUserId : int.tryParse(rawUserId?.toString() ?? '');
        if (userId != null && conversationArgs?.otherUserId == userId) {
          final isOnline = payload['is_online'] as bool? ?? false;
          if (mounted && _isOtherUserOnline != isOnline) {
            setState(() {
              _isOtherUserOnline = isOnline;
            });
          }
        }
      },
    );
  }

  void _handleNewMessage(Map<String, dynamic> json) async {
    log(
      'new message: $json',
      name: 'ChatInboxScreen',
    );

    final message = ChatMessage.fromJson(
      json,
      currentUserId: _myId,
    );

    final senderId = int.tryParse(message.senderId) ?? 0;

    final hasProfile =
        inboxBloc?.userProfiles.containsKey(senderId) ?? false;

    await inboxBloc?.handleNewMessage(
      message: message,
      profile: senderId > 0 && !hasProfile
          ? ReadReceiptUser(
        userId: senderId,
        name: message.senderName,
        avatarUrl: message.senderAvatar,
      )
          : null,
    );

    if (!message.isMine) {
      _checkAndSendSeenAck();
    }
  }

  void _handleStatusUpdated(Map<String, dynamic> json) {
    final statusMessageId =
        json['message_id']?.toString() ??
            json['upto_message_id']?.toString();

    final status = json['status'] as String?;

    if (statusMessageId == null) return;

    final targetId = int.tryParse(statusMessageId) ?? 0;

    final isSeenEvent = status == 'seen';
    final isDeliveredEvent = status == 'delivered';

    if (!isSeenEvent && !isDeliveredEvent) return;

    final items = inboxBloc?.cursorPageHolder.items ?? [];
    if (items.isEmpty) return;

    var changed = false;

    final updated = items.map((item) {
      if (!item.isMine) return item;

      final currentId = int.tryParse(item.id) ?? 0;

      if (currentId <= 0 || currentId > targetId) return item;

      if (isSeenEvent && !item.isSeen) {
        changed = true;
        return item.copyWith(
          isSeen: true,
          isDelivered: true,
        );
      } else if (isDeliveredEvent && !item.isDelivered && !item.isSeen) {
        changed = true;
        return item.copyWith(
          isDelivered: true,
        );
      }

      return item;
    }).toList();

    if (changed) {
      inboxBloc?.replaceLocalItems(updated, emitState: true);
    }
  }

  void _handleMemberReadWatermark(
      Map<String, dynamic> json,
      ) {
    final userId = int.tryParse(
      json['user_id']?.toString() ?? '',
    );

    final messageId = int.tryParse(
      json['last_read_message_id']?.toString() ?? '',
    );

    if (userId == null || userId <= 0) return;
    if (messageId == null || messageId <= 0) return;

    final userName = json['user_name'] as String? ?? '';
    final userAvatar = json['user_avatar'] as String? ?? '';

    inboxBloc?.handleMemberWatermark(
      userId: userId,
      messageId: messageId,
      profile: (userName.isNotEmpty || userAvatar.isNotEmpty)
          ? ReadReceiptUser(
              userId: userId,
              name: userName,
              avatarUrl: userAvatar,
            )
          : null,
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || conversationArgs?.id == null) return;
    inboxBloc?.sendOutgoingMessage(
      content: text,
      currentUserId: _myId,
    );
    _controller.clear();
  }



  @override
  void dispose() {
    if (inboxBloc != null) {
      ChatSyncCoordinator.instance.unregisterActiveBloc(inboxBloc!);
    }
    _removeNewMessageListener?.call();
    _removeStatusUpdatedListener?.call();
    _removeWatermarkListener?.call();
    _removePresenceListener?.call();

    _blocSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (inboxBloc == null) return const SizedBox();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        title: Row(
          children: [
            CuteAvatar(
              name: conversationArgs?.displayTitle ?? '',
              imageUrl: conversationArgs?.avatarUrl,
              isGroup: conversationArgs?.isGroup == true,
              isOnline: conversationArgs?.isGroup != true && _isOtherUserOnline,
              size: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    conversationArgs?.displayTitle ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    conversationArgs?.isGroup == true
                        ? 'group'
                        : (_isOtherUserOnline ? 'online' : 'offline'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: conversationArgs?.isGroup == true
                          ? AppColors.neutralColor.shade400
                          : (_isOtherUserOnline
                              ? AppColors.onlineGreen
                              : AppColors.neutralColor.shade400),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (conversationArgs?.isGroup == true)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'group_info') {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          GroupInfoScreen(conversation: conversationArgs!),
                    ),
                  );
                  if (result == true && context.mounted) {
                    Navigator.pop(context);
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'group_info',
                  child: Text('Group Info'),
                ),
              ],
            )
          else
            PopupMenuButton<String>(
              onSelected: (value) async {
                final isVideo = value == 'video_call';
                final hasPermission = await CallPermissionService.instance
                    .requestPermissions(isVideo: isVideo);
                if (!hasPermission) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isVideo
                              ? 'Camera and microphone permissions are required for video calls.'
                              : 'Microphone permission is required for voice calls.',
                        ),
                        action: SnackBarAction(
                          label: 'Settings',
                          onPressed: () =>
                              CallPermissionService.instance.openSettings(),
                        ),
                      ),
                    );
                  }
                  return;
                }

                int? targetId = conversationArgs?.otherUserId;
                if (targetId == null || targetId == 0) {
                  final items = inboxBloc?.cursorPageHolder.items ?? [];
                  for (final m in items) {
                    if (!m.isMine) {
                      targetId = int.tryParse(m.senderId);
                      break;
                    }
                  }
                }

                if (targetId != null && targetId > 0 && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CallScreen(
                        targetUserId: targetId!,
                        userName: conversationArgs?.displayTitle ?? 'User',
                        avatarUrl: conversationArgs?.avatarUrl != null
                            ? _getFullUrl(conversationArgs!.avatarUrl)
                            : '',
                        isVideo: isVideo,
                        isIncoming: false,
                      ),
                    ),
                  );
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Cannot initiate call: recipient ID not found',
                      ),
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'audio_call',
                  child: Row(
                    children: [
                      Icon(Icons.call, size: 20),
                      SizedBox(width: 10),
                      Text('Voice call'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'video_call',
                  child: Row(
                    children: [
                      Icon(Icons.videocam, size: 20),
                      SizedBox(width: 10),
                      Text('Video call'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          image: DecorationImage(
            image: AssetImage(Assets.lightBg.path),
            fit: BoxFit.cover,
            opacity: 0.08,
          ),
        ),
        child: Column(
          children: [
            inboxBloc!.build(
              builder: (context, state) {
                final data = inboxBloc?.cursorPageHolder.items ?? [];

                // Chronological cascade: iterates NEWEST (index 0) -> OLDEST (index N).
                // Rule: If a newer message is seen, all older messages must also be seen.
                // Rule: If a newer message is delivered, all older messages must also be delivered.

                return Expanded(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.only(bottom: 8, top: 8),
                    controller: cursorScrollController?.controller,
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final newModel = data.elementAt(index);
                      final isGroup = conversationArgs?.isGroup == true;

                      // Newer message (the one below this message on the screen)
                      final newerModel = index > 0
                          ? data.elementAt(index - 1)
                          : null;

                      // Older message (the one above this message on the screen)
                      final oldModel = index + 1 < data.length
                          ? data.elementAt(index + 1)
                          : null;

                      bool hasOlderSameSender = false;
                      if (oldModel != null) {
                        final gapOlder = (newModel.sentAt.millisecondsSinceEpoch -
                                oldModel.sentAt.millisecondsSinceEpoch)
                            .abs();
                        final sameDay = oldModel.timeStamp?.dateCompare ==
                            newModel.timeStamp?.dateCompare;
                        hasOlderSameSender = oldModel.senderId == newModel.senderId &&
                            gapOlder < 600000 &&
                            sameDay;
                      }

                      bool hasNewerSameSender = false;
                      if (newerModel != null) {
                        final gapNewer = (newModel.sentAt.millisecondsSinceEpoch -
                                newerModel.sentAt.millisecondsSinceEpoch)
                            .abs();
                        final sameDay = newerModel.timeStamp?.dateCompare ==
                            newModel.timeStamp?.dateCompare;
                        hasNewerSameSender = newerModel.senderId == newModel.senderId &&
                            gapNewer < 600000 &&
                            sameDay;
                      }

                      BubblePosition position = BubblePosition.single;
                      if (!hasOlderSameSender && hasNewerSameSender) {
                        position = BubblePosition.first;
                      } else if (hasOlderSameSender && hasNewerSameSender) {
                        position = BubblePosition.middle;
                      } else if (hasOlderSameSender && !hasNewerSameSender) {
                        position = BubblePosition.last;
                      }

                      // Profile visibility: only on the last message of the sequence (or single)
                      final showProfile = isGroup && !newModel.isMine && !hasNewerSameSender;

                      // Sender name: only on the first message of the sequence (or single)
                      final showSenderName = isGroup && !newModel.isMine && !hasOlderSameSender;

                      // Date indicator: if day changed or oldest message
                      final todayIndicator = oldModel == null ||
                          oldModel.timeStamp?.dateCompare !=
                              newModel.timeStamp?.dateCompare;

                      return designMessage(
                        newModel,
                        _resendMessage,
                        oldModel != null,
                        oldModel?.sentAt.millisecondsSinceEpoch ?? 0,
                        todayIndicator,
                        showSenderName,
                        showProfile,
                        isGroup,
                        position: position,
                        isSameSenderAbove: oldModel != null &&
                            oldModel.senderId == newModel.senderId,
                        readBy: inboxBloc?.getWatermarkUsers(newModel.id),
                        readCount: inboxBloc?.getWatermarkCount(newModel.id),
                      );
                    },
                  ),
                );
              },
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(
                    color: AppColors.neutralColor.shade100,
                    width: 1.0,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.neutralColor.shade100,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.neutralColor.shade900,
                                ),
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  hintText: 'Type a message...',
                                  hintStyle: TextStyle(
                                    fontSize: 14.5,
                                    color: AppColors.neutralColor.shade400,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.cyanAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cyanAccent.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: _send,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
