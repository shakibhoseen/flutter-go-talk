import 'dart:async';
import 'dart:developer';

import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';

import '../../data/chat_repository.dart';
import '../../data/http_chat_repository.dart';
import '../../../../core/db/network/socket/socket_event.dart';
import '../../model/chat_user.dart';
import '../../model/conversation.dart';

import 'package:flutter/material.dart';

import '../../../../core/navigation/navigation_service.dart';
import '../../../call/data/service/call_signaling_service.dart';
import '../../../call/presentation/call_screen.dart';
import '../../../call/presentation/widgets/incoming_call_dialog.dart';
import '../../../call/data/service/call_permission_service.dart';
import '../../../chat_inbox/data/outbox/chat_sync_coordinator.dart';
import '../../../../core/session/auth_session.dart';

class ChatViewModel {
  ChatViewModel({
    ChatRepository? repository,
    ChatSyncCoordinator? syncCoordinator,
  })  : repository = repository ?? const HttpChatRepository(),
        syncCoordinator = syncCoordinator ?? ChatSyncCoordinator.instance {
    conversationsBloc.setFunction(
      attach: (_) => this.repository.getConversations(),
    );
    allUsersBloc.setFunction(attach: (_) => this.repository.getAllUsers());
    conversationsBloc.execute();
    allUsersBloc.execute();

    _socketSubscription = ChatSocketService.instance.messages.listen(
      _handleMultipleRaw,
    );
    this.syncCoordinator.registerConversationsSync(refreshConversations);
    this.syncCoordinator.registerConversationRemoved(removeConversation);
  }

  void _handleMultipleRaw(dynamic raw) {
    final events = decodeSocketEvents(raw);

    for (final event in events) {
      _handleSocketEvent(event);
    }
  }

  final ChatRepository repository;
  final ChatSyncCoordinator syncCoordinator;
  final conversationsBloc = SimpleBlocParent<List<Conversation>>();
  final allUsersBloc = SimpleBlocParent<List<ChatUser>>();

  StreamSubscription<dynamic>? _socketSubscription;
  bool _isRefreshingConversations = false;
  bool get isRefreshingConversations => _isRefreshingConversations;

  @visibleForTesting
  void handleSocketEventForTesting(Map<String, dynamic> event) {
    _handleSocketEvent(event);
  }

  void _handleSocketEvent(Map<String, dynamic> event) {
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
      case 'user_presence':
        _handleUserPresence(event['payload']);
        break;
    }
  }

  void _handleUserPresence(dynamic payload) {
    if (payload is! Map) return;
    final json = Map<String, dynamic>.from(payload);
    final rawUserId = json['user_id'];
    final userId = rawUserId?.toString() ?? '';
    final isOnline = json['is_online'] as bool? ?? false;
    if (userId.isEmpty) return;

    final usersState = allUsersBloc.state;
    if (usersState is SuccessState<List<ChatUser>>) {
      var changed = false;
      final updated = usersState.data.map((u) {
        if (u.id == userId && u.isOnline != isOnline) {
          changed = true;
          return u.copyWith(isOnline: isOnline);
        }
        return u;
      }).toList();
      if (changed) {
        allUsersBloc.emitSuccess(updated);
      }
    }

    final convsState = conversationsBloc.state;
    if (convsState is SuccessState<List<Conversation>>) {
      final parsedUid = int.tryParse(userId);
      var changed = false;
      final updated = convsState.data.map((c) {
        if (!c.isGroup && c.otherUserId == parsedUid && c.isOnline != isOnline) {
          changed = true;
          return c.copyWith(isOnline: isOnline);
        }
        return c;
      }).toList();
      if (changed) {
        conversationsBloc.emitSuccess(updated);
      }
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
          final hasPermission = await CallPermissionService.instance
              .requestPermissions(isVideo: isVideo);
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
                    onPressed: () =>
                        CallPermissionService.instance.openSettings(),
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
                  offerSdp: signalData is Map
                      ? Map<String, dynamic>.from(signalData)
                      : null,
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

    final content = message['content'] as String?;
    final senderId = message['sender_id'] as int?;
    final messageId = message['id']?.toString();
    final conversationType =
        message['conversation_type'] as String? ?? 'direct';




    final state = conversationsBloc.state;
    if (state is! SuccessState<List<Conversation>>) return;

    final at = DateTime.tryParse(message['created_at'] as String? ?? '');

    final conversations = List<Conversation>.from(state.data);
    final index = conversations.indexWhere((c) => c.id == conversationId);

    if (index != -1) {
      final parsedMsgId = messageId != null ? int.tryParse(messageId) : null;
      final updated = conversations
          .removeAt(index)
          .copyWithNewMessage(messageId: parsedMsgId, content: content, senderId: senderId, at: at);
      conversations.insert(0, updated);

      if (updated.title == null || updated.title!.isEmpty) {
        refreshConversations();
      }
    } else {
      final parsedMsgId = messageId != null ? int.tryParse(messageId) : null;
      final isGroup = conversationType.toLowerCase() == 'group';
      final myIdStr = AuthSession.tokens?.user?.id?.toString();
      final myId = myIdStr != null ? int.tryParse(myIdStr) : null;

      // Group title must NEVER be the message sender's name.
      // Direct title is only set to sender_name if sender is the other party.
      String? title;
      if (!isGroup) {
        if (senderId != null && myId != null) {
          if (senderId != myId) {
            title = message['sender_name'] as String?;
          }
        } else {
          title = message['sender_name'] as String?;
        }
      }

      conversations.insert(
        0,
        Conversation(
          id: conversationId,
          type: conversationType,
          title: title,
          lastMessageId: parsedMsgId,
          lastMessageContent: content,
          lastMessageSenderId: senderId,
          lastMessageAt: at,
          createdAt: at ?? DateTime.now(),
        ),
      );

      // Trigger background refresh so authoritative conversation details (like group title) are fetched
      refreshConversations();
    }

    conversationsBloc.emitSuccess(conversations);
  }

  @visibleForTesting
  void handleNewMessageForTest(dynamic payload) => _handleNewMessage(payload);

  /// Adds a new conversation or updates an existing one in the active list.
  /// Ensures newly created direct or group conversations immediately appear
  /// in the conversations list without waiting for a message or network refresh.
  void addOrUpdateConversation(Conversation conversation) {
    final state = conversationsBloc.state;
    final current = state is SuccessState<List<Conversation>>
        ? List<Conversation>.from(state.data)
        : <Conversation>[];

    final index = current.indexWhere((c) => c.id == conversation.id);
    if (index != -1) {
      current[index] = conversation;
    } else {
      current.insert(0, conversation);
    }

    current.sort((a, b) {
      final timeA = a.lastMessageAt ?? a.createdAt;
      final timeB = b.lastMessageAt ?? b.createdAt;
      return timeB.compareTo(timeA);
    });

    conversationsBloc.emitSuccess(current);
  }

  /// Removes a conversation from the active list.
  /// Used when a user leaves or deletes a group conversation.
  void removeConversation(String conversationId) {
    final state = conversationsBloc.state;
    if (state is SuccessState<List<Conversation>>) {
      final updated = state.data.where((c) => c.id != conversationId).toList();
      conversationsBloc.emitSuccess(updated);
    }
  }

  /// Background refresh of conversations from `GET /conversations`.
  /// Uses [emitSuccess] to avoid replacing the active list with a loading spinner.
  Future<void> refreshConversations() async {
    // Avoid duplicate requests if initial load is still in flight or a refresh is active
    final isInitialPending =
        conversationsBloc.isLoading || conversationsBloc.state is InitialState;
    if (isInitialPending || _isRefreshingConversations) {
      log(
        'Conversations refresh skipped: already loading or refresh in flight',
        name: 'ChatViewModel',
      );
      return;
    }

    _isRefreshingConversations = true;
    try {
      final fresh = await repository.getConversations();
      _mergeAndEmitConversations(fresh);
    } catch (e, st) {
      log(
        'Failed to refresh conversations: $e',
        name: 'ChatViewModel',
        stackTrace: st,
      );
    } finally {
      _isRefreshingConversations = false;
    }
  }

  void _mergeAndEmitConversations(List<Conversation> fresh) {
    final state = conversationsBloc.state;
    if (state is! SuccessState<List<Conversation>>) {
      conversationsBloc.emitSuccess(fresh);
      return;
    }

    final current = state.data;
    final currentMap = {for (final c in current) c.id: c};

    // Monotonic merge: ensure an in-memory head (e.g. from a live WebSocket
    // new_message that arrived while GET /conversations was in flight) is not downgraded.
    final merged = fresh.map((inc) {
      final existing = currentMap[inc.id];
      if (existing == null) return inc;
      if (_isExistingNewer(existing, inc)) {
        return existing.copyWith(
          title: (inc.isGroup && inc.title != null && inc.title!.isNotEmpty)
              ? inc.title
              : (existing.title ?? inc.title),
          avatarUrl: existing.avatarUrl ?? inc.avatarUrl,
          otherUserId: existing.otherUserId ?? inc.otherUserId,
        );
      }
      if ((inc.title == null || inc.title!.isEmpty) &&
          existing.title != null &&
          existing.title!.isNotEmpty) {
        return inc.copyWith(title: existing.title);
      }
      return inc;
    }).toList();

    // Preserve any existing conversation that was not returned in the fresh list
    final incomingIds = {for (final inc in fresh) inc.id};
    for (final curr in current) {
      if (!incomingIds.contains(curr.id)) {
        merged.add(curr);
      }
    }

    // Preserve recency ordering: newest lastMessageAt (or createdAt) first
    merged.sort((a, b) {
      final timeA = a.lastMessageAt ?? a.createdAt;
      final timeB = b.lastMessageAt ?? b.createdAt;
      return timeB.compareTo(timeA);
    });

    conversationsBloc.emitSuccess(merged);
  }

  bool _isExistingNewer(Conversation existing, Conversation incoming) {
    final existId = existing.lastMessageId;
    final incId = incoming.lastMessageId;
    if (existId != null && incId != null) {
      if (existId != incId) {
        return existId > incId;
      }
    } else if (existId != null && incId == null) {
      return true;
    }

    final existAt = existing.lastMessageAt;
    final incAt = incoming.lastMessageAt;
    if (existAt != null && incAt != null) {
      if (existAt != incAt) {
        return existAt.isAfter(incAt);
      }
    } else if (existAt != null && incAt == null) {
      return true;
    }

    return false;
  }

  void dispose() {
    syncCoordinator.unregisterConversationsSync();
    _socketSubscription?.cancel();
  }
}
