import 'dart:async';

import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';

import '../../data/chat_repository.dart';
import '../../data/http_chat_repository.dart';
import '../../data/socket_event.dart';
import '../../model/chat_user.dart';
import '../../model/conversation.dart';

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
        // TODO: incoming-call popup — not built yet.
        break;
    }
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
