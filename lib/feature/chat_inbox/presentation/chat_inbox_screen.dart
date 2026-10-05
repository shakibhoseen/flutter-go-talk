import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/config/app_flavor_config.dart';
import 'package:whatsapp_flutter_go/core/db/network/network_service_type.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/group/presentation/group_info_screen.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/presentation/widgets/message_design.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';

import '../../../core/controllers/my_scroll_controller.dart';
import '../../../core/db/network/socket/chat_socket_event_dispatcher.dart';
import '../../../core/db/network/socket/chat_socket_event_type.dart';
import '../../../core/db/network/socket/chat_socket_service.dart';
import '../../../core/session/auth_session.dart';
import '../../../gen/assets.gen.dart';
import '../../../core/db/network/socket/socket_event.dart';
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

  String _getFullUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    // We assume AppFlavorConfig is imported, but we might need to add import
    final baseUrl = AppFlavorConfig.baseUrlFor(NetworkServiceType.chat);
    return '$baseUrl/$path';
  }

  void _checkAndSendSeenAck() {
    final items = inboxBloc?.cursorPageHolder.items ?? [];
    if (items.isNotEmpty && conversationArgs?.id != null) {
      final latestMessage = items.first;
      if (!latestMessage.isMine && _lastAckedMessageId != latestMessage.id) {
        _lastAckedMessageId = latestMessage.id;
        ChatSocketService.instance.sendSeenAck(
          conversationId: conversationArgs!.id,
          messageId: latestMessage.id,
          senderId: int.tryParse(latestMessage.senderId) ?? 0,
        );
      }
    }
  }

  void _resendMessage() {}

  @override
  void initState() {
    conversationArgs = NavigationService.getArguments<Conversation>();
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

    }

    super.initState();
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
  }

  void _handleNewMessage(Map<String, dynamic> json) {
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

    inboxBloc?.handleNewMessage(
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

    final items =
        inboxBloc?.cursorPageHolder.items ?? [];

    var changed = false;

    for (final item in items) {
      if (!item.isMine) continue;

      final currentId = int.tryParse(item.id) ?? 0;

      if (currentId > targetId) continue;

      if (isSeenEvent && !item.isSeen) {
        inboxBloc?.upsertLocalItem(
          item.copyWith(
            isSeen: true,
            isDelivered: true,
          ),
          emitState: false,
        );

        changed = true;
      } else if (
      isDeliveredEvent &&
          !item.isDelivered &&
          !item.isSeen
      ) {
        inboxBloc?.upsertLocalItem(
          item.copyWith(
            isDelivered: true,
          ),
          emitState: false,
        );

        changed = true;
      }
    }

    if (changed) {
      inboxBloc?.emitCurrentLocalData();
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

    inboxBloc?.handleMemberWatermark(
      userId: userId,
      messageId: messageId,
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ChatSocketService.instance.sendMessage(
      conversationId: conversationArgs!.id,
      content: text,
    );
    _controller.clear();
  }



  @override
  void dispose() {
    _removeNewMessageListener?.call();
    _removeStatusUpdatedListener?.call();
    _removeWatermarkListener?.call();

    _blocSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (inboxBloc == null) return const SizedBox();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: conversationArgs?.avatarUrl != null
                  ? NetworkImage(_getFullUrl(conversationArgs!.avatarUrl))
                  : null,
              child: conversationArgs?.avatarUrl == null
                  ? Icon(
                      conversationArgs?.isGroup == true
                          ? Icons.groups
                          : Icons.person,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                conversationArgs?.displayTitle ?? '',
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (conversationArgs?.isGroup == true)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'group_info') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          GroupInfoScreen(conversation: conversationArgs!),
                    ),
                  );
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
          color: Colors.green.shade200,
          image: DecorationImage(
            image: AssetImage(Assets.lightBg.path),
            fit: BoxFit.cover,
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
                    padding: const EdgeInsets.only(bottom: 8),
                    controller: cursorScrollController?.controller,
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final newModel = data.elementAt(index);
                      final isGroup = conversationArgs?.isGroup == true;

                      // Newer message (the one below this message on the screen)
                      final newerModel = index > 0
                          ? data.elementAt(index - 1)
                          : null;

                      // Profile visibility logic (only applicable for group chats)
                      bool showProfile = false;
                      if (isGroup && !newModel.isMine) {
                        if (newerModel == null) {
                          // This is the absolute newest message in the whole chat
                          showProfile = true;
                        } else if (newerModel.senderId != newModel.senderId) {
                          // The message below is from a different sender
                          showProfile = true;
                        } else {
                          // Same sender below. Check time gap.
                          // If gap is medium or big (>= 10 minutes), show profile here too.
                          final gap =
                              (newModel.sentAt.millisecondsSinceEpoch -
                                      newerModel.sentAt.millisecondsSinceEpoch)
                                  .abs();
                          if (gap >= 600000) {
                            showProfile = true;
                          }
                        }
                      }

                      // Oldest message edge case
                      if (index + 1 == data.length) {
                        return designMessage(
                          newModel,
                          _resendMessage,
                          false,
                          // isCompare
                          0,
                          // before (time)
                          true,
                          // todayIndicator
                          isGroup ? !newModel.isMine : false,
                          // showSenderName (top message shows name only in groups)
                          showProfile,
                          isGroup,
                          readBy: inboxBloc?.getWatermarkUsers(newModel.id),
                          readCount: inboxBloc?.getWatermarkCount(newModel.id),
                        );
                      }

                      // Older message (the one above this message on the screen)
                      final oldModel = data.elementAt(index + 1);

                      bool todayIndicator = false;
                      bool showSenderName = false;

                      if (isGroup && !newModel.isMine) {
                        if (oldModel.senderId != newModel.senderId) {
                          showSenderName = true;
                        } else {
                          // Same sender, but check if there's a large time gap
                          final gap =
                              (oldModel.sentAt.millisecondsSinceEpoch -
                                      newModel.sentAt.millisecondsSinceEpoch)
                                  .abs();
                          if (gap >= 600000) {
                            // 10 minutes
                            showSenderName = true;
                          }
                        }
                      }

                      if (oldModel.timeStamp?.dateCompare !=
                          newModel.timeStamp?.dateCompare) {
                        todayIndicator = true;
                      }

                      return designMessage(
                        newModel,
                        _resendMessage,
                        true,
                        // isCompare
                        oldModel.sentAt.millisecondsSinceEpoch,
                        todayIndicator,
                        showSenderName,
                        showProfile,
                        isGroup,
                        readBy: inboxBloc?.getWatermarkUsers(newModel.id),
                        readCount: inboxBloc?.getWatermarkCount(newModel.id),
                      );
                    },
                  ),
                );
              },
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.send), onPressed: _send),
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
