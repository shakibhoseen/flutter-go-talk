import 'dart:async';

import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/presentation/widgets/message_design.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_message.dart';

import '../../../core/controllers/my_scroll_controller.dart';
import '../../../core/db/network/socket/chat_socket_service.dart';
import '../../../core/session/auth_session.dart';
import '../../../gen/assets.gen.dart';
import '../../home/data/socket_event.dart';
import '../../home/model/conversation.dart';

class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  InboxMessageListCursorBloc? inboxBloc;
  final _controller = TextEditingController();
  Conversation? conversationArgs;
  StreamSubscription<dynamic>? _socketSubscription;

  String? get _myId => AuthSession.tokens?.user?.id?.toString();
  MyCursorScrollController? cursorScrollController;

  void _resendMessage() {}

  @override
  void initState() {
    conversationArgs = NavigationService.getArguments<Conversation>();
    if (conversationArgs?.id != null) {
      inboxBloc = InboxMessageListCursorBloc(
        conversationId: conversationArgs!.id,
      );
      inboxBloc?.execute();
      cursorScrollController = MyCursorScrollController(
        inboxBloc!,
        () {
          inboxBloc?.execute();
        },
        cursorDataHolder: inboxBloc!.cursorPageHolder,
        isReverse: true,
      );
    }
    _socketSubscription = ChatSocketService.instance.messages.listen(
      _handleSocketEvent,
    );

    super.initState();
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

  void _handleSocketEvent(dynamic raw) {
    final event = decodeSocketEvent(raw);
    if (event == null) return;

    final type = event['type'];
    final payload = event['payload'];
    if (payload is! Map) return;
    final json = Map<String, dynamic>.from(payload);
    if (json['conversation_id']?.toString() != conversationArgs?.id) return;

    if (type == 'new_message') {
      final message = ChatMessage.fromJson(json, currentUserId: _myId);
      inboxBloc?.upsertLocalItem(message);
      if (!message.isMine) {
        ChatSocketService.instance.sendSeenAck(
          conversationId: conversationArgs!.id,
          messageId: message.id,
          senderId: int.tryParse(message.senderId) ?? 0,
        );
      }
    } else if (type == 'ack_seen' || type == 'message_seen') {
      final seenMessageId = json['message_id']?.toString();
      if (seenMessageId != null) {
        final items = inboxBloc?.cursorPageHolder.items ?? [];
        bool changed = false;
        for (final item in items) {
          if (item.isMine && !item.isSeen) {
            inboxBloc?.upsertLocalItem(
              item.copyWith(isSeen: true),
              emitState: false,
            );
            changed = true;
          }
        }
        if (changed) {
          inboxBloc?.emitCurrentLocalData();
        }
      }
    }
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (inboxBloc == null) return const SizedBox();
    return Scaffold(
      appBar: AppBar(title: Text('inbox')),
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
                if (data.isNotEmpty) {
                  final latestMessage = data.first;
                  if (!latestMessage.isMine && !latestMessage.isSeen) {
                    ChatSocketService.instance.sendSeenAck(
                      conversationId: conversationArgs!.id,
                      messageId: latestMessage.id,
                      senderId: int.tryParse(latestMessage.senderId) ?? 0,
                    );
                  }
                }
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
                      final newerModel = index > 0 ? data.elementAt(index - 1) : null;
                      
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
                          final gap = (newModel.sentAt.millisecondsSinceEpoch - 
                                       newerModel.sentAt.millisecondsSinceEpoch).abs();
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
                          false, // isCompare
                          0,     // before (time)
                          true,  // todayIndicator
                          isGroup ? !newModel.isMine : false, // showSenderName (top message shows name only in groups)
                          showProfile,
                          isGroup
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
                          final gap = (oldModel.sentAt.millisecondsSinceEpoch - 
                                       newModel.sentAt.millisecondsSinceEpoch).abs();
                          if (gap >= 600000) { // 10 minutes
                            showSenderName = true;
                          }
                        }
                      }

                      if (oldModel.timeStamp?.dateCompare != newModel.timeStamp?.dateCompare) {
                        todayIndicator = true;
                      }

                      return designMessage(
                        newModel,
                        _resendMessage,
                        true, // isCompare
                        oldModel.sentAt.millisecondsSinceEpoch,
                        todayIndicator,
                        showSenderName,
                        showProfile,
                        isGroup
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
