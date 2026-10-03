import 'dart:async';

import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';

import '../../data/chat_repository.dart';
import '../../data/http_chat_repository.dart';
import '../../data/socket_event.dart';
import '../../model/chat_user.dart';
import '../../model/conversation.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:flutter/material.dart';
import '../../../../core/navigation/navigation_service.dart';
import '../../../call/data/service/call_signaling_service.dart';
import '../../../call/presentation/call_screen.dart';
import '../../../call/presentation/widgets/incoming_call_dialog.dart';
import '../../../call/data/service/call_permission_service.dart';

class ChatViewModel {
  ChatViewModel({ChatRepository? repository})
    : repository = repository ?? const HttpChatRepository() {
    conversationsBloc.setFunction(
      attach: (_) => this.repository.getConversations(),
    );
    allUsersBloc.setFunction(attach: (_) => this.repository.getAllUsers());
    conversationsBloc.execute();
    allUsersBloc.execute();

    _socketSubscription = ChatSocketService.instance.messages.listen(
      _handleSocketEvent,
    );
  }

  final ChatRepository repository;
  final conversationsBloc = SimpleBlocParent<List<Conversation>>();
  final allUsersBloc = SimpleBlocParent<List<ChatUser>>();

  StreamSubscription<dynamic>? _socketSubscription;

  void _handleSocketEvent(dynamic raw) {
    final event = decodeSocketEvent(raw);
    if (event == null) return;

    switch (event['type']) {
      case 'new_message':
        _handleNewMessage(event['payload']);
        break;
      case 'status_updated':
        // TODO: tick-mark (sent/delivered/seen) updates — no UI for this yet.
        break;
      case 'call_offer':
        _handleIncomingCall(event['payload']);
        break;
    }
  }

  void _handleIncomingCall(dynamic payload) {
    if (payload is! Map) return;
    final json = Map<String, dynamic>.from(payload);
    final fromUserId = json['from_user_id'] as int? ?? 0;
    final isVideo = json['is_video'] as bool? ?? false;
    final signalData = json['signal_data'];

    final context = NavigationService.navigatorKey.currentContext;
    if (context == null || fromUserId <= 0) return;

    String callerName = 'User $fromUserId';
    String callerAvatar = '';

    final usersState = allUsersBloc.state;
    if (usersState is SuccessState<List<ChatUser>>) {
      final user = usersState.data.cast<ChatUser?>().firstWhere(
        (u) => u?.id == fromUserId.toString(),
        orElse: () => null,
      );
      if (user != null) {
        callerName = user.name;
        callerAvatar = user.avatarUrl;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => IncomingCallDialog(
        callerName: callerName,
        callerAvatar: callerAvatar,
        isVideo: isVideo,
        onAccept: () async {
          Navigator.pop(dialogContext);
          final hasPermission = await CallPermissionService.instance.requestPermissions(isVideo: isVideo);
          if (!hasPermission) {
            CallSignalingService.instance.sendEndCall(targetUserId: fromUserId);
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
                    onPressed: () => CallPermissionService.instance.openSettings(),
                  ),
                ),
              );
            }
            return;
          }

          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CallScreen(
                  targetUserId: fromUserId,
                  userName: callerName,
                  avatarUrl: callerAvatar,
                  isVideo: isVideo,
                  isIncoming: true,
                  offerSdp: signalData is Map ? Map<String, dynamic>.from(signalData) : null,
                ),
              ),
            );
          }
        },
        onDecline: () {
          Navigator.pop(dialogContext);
          CallSignalingService.instance.sendEndCall(targetUserId: fromUserId);
        },
      ),
    );
  }

  /// Moves the conversation a message just landed in to the top of the list
  /// and refreshes its preview; if it's a conversation this session hasn't
  /// fetched yet, inserts it directly rather than waiting on a refetch.
  void _handleNewMessage(dynamic payload) {
    if (payload is! Map) return;
    final message = Map<String, dynamic>.from(payload);

    final conversationId = message['conversation_id'] as String?;
    if (conversationId == null) return;

    final state = conversationsBloc.state;
    if (state is! SuccessState<List<Conversation>>) return;

    final content = message['content'] as String?;
    final senderId = message['sender_id'] as int?;
    final messageId = message['id']?.toString();
    final conversationType = message['conversation_type'] as String? ?? 'direct';
    final myIdStr = AuthSession.tokens?.user?.id?.toString();
    final myId = myIdStr != null ? int.tryParse(myIdStr) : null;

    // Only send ack_delivered for 1-to-1 chats to avoid group N x N broadcast spam
    if (messageId != null && senderId != null && senderId != myId && conversationType != 'group') {
      ChatSocketService.instance.sendDeliveredAck(
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
      );
    }
    final at = DateTime.tryParse(message['created_at'] as String? ?? '');

    final conversations = List<Conversation>.from(state.data);
    final index = conversations.indexWhere((c) => c.id == conversationId);

    if (index != -1) {
      final updated = conversations.removeAt(index).copyWithNewMessage(
        content: content,
        senderId: senderId,
        at: at,
      );
      conversations.insert(0, updated);
    } else {
      conversations.insert(
        0,
        Conversation(
          id: conversationId,
          type: message['conversation_type'] as String? ?? 'direct',
          title: message['sender_name'] as String?,
          lastMessageContent: content,
          lastMessageSenderId: senderId,
          lastMessageAt: at,
          createdAt: at ?? DateTime.now(),
        ),
      );
    }

    conversationsBloc.emitSuccess(conversations);
  }

  void dispose() {
    _socketSubscription?.cancel();
  }
}
