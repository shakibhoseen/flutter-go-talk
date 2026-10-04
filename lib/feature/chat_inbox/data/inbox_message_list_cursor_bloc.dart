import 'package:either_dart/either.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/local_sync_cursor_pagination_bloc.dart';

import '../../../core/session/auth_session.dart';
import '../../home/data/http_chat_repository.dart';
import '../../home/model/chat_message.dart';

class InboxMessageListCursorBloc
    extends LocalSyncCursorPaginationBloc<ChatMessage> {
  final repository = HttpChatRepository();
  final pageSize = 20;
  final String conversationId;
  final bool isGroup;

  InboxMessageListCursorBloc({
    required this.conversationId,
    this.isGroup = false,
  }) : super(InitialState());

  @override
  String itemIdentity(ChatMessage item) => item.id;

  @override
  Future<Either<CursorPaginationResponse<ChatMessage>, String>> handleEvent(
    event,
  ) async {
    final response = await repository.getMessages(
      conversationId,
      limit: pageSize,
      beforeId: nextCursor,
    );

    setCursor(model: response);
    return Left(response);
  }

  final Map<int, String> userLastMessageSeenID = {};
  final Map<int, ReadReceiptUser> userProfiles = {};

  void execute({bool? pageFromStart}) {
    add(FetchDataWithQueryEvent(
        query: {},
        clearPageWithNewData: pageFromStart ?? false));
  }

  @override
  void doActionBeforeEmitSuccessWithPaginationState(
    SuccessWithPaginationState<CursorPaginationResponse<ChatMessage>> state,
  ) {
    super.doActionBeforeEmitSuccessWithPaginationState(state);

    final extraWatermarks = state.data.extra?['watermarks'];
    if (extraWatermarks is Map) {
      extraWatermarks.forEach((msgId, data) {
        if (data is Map) {
          final usersList = (data['users'] as List<dynamic>?)
              ?.map((e) => ReadReceiptUser.fromJson(Map<String, dynamic>.from(e)))
              .toList() ?? [];
          final msgIdStr = msgId.toString();
          for (final u in usersList) {
            userProfiles[u.userId] = u;
            userLastMessageSeenID.putIfAbsent(u.userId, () => msgIdStr);
          }
        }
      });
    }

    _applyLatestWatermarkResolution(emitState: false);
  }

  void updateMemberWatermark({
    required int userId,
    required String messageId,
    String name = '',
    String avatarUrl = '',
  }) {
    if (userId <= 0 || messageId.isEmpty) return;

    if (name.isNotEmpty || avatarUrl.isNotEmpty) {
      userProfiles[userId] = ReadReceiptUser(
        userId: userId,
        name: name,
        avatarUrl: avatarUrl,
      );
    }

    userLastMessageSeenID[userId] = messageId;
    _applyLatestWatermarkResolution(emitState: true);
  }

  List<ReadReceiptUser> getWatermarkUsers(String messageId) {
    final list = <ReadReceiptUser>[];
    userLastMessageSeenID.forEach((userId, targetMsgId) {
      if (targetMsgId == messageId) {
        final profile = userProfiles[userId];
        if (profile != null) list.add(profile);
      }
    });
    return list;
  }

  int getWatermarkCount(String messageId) {
    int count = 0;
    userLastMessageSeenID.forEach((userId, targetMsgId) {
      if (targetMsgId == messageId) count++;
    });
    return count;
  }

  void _applyLatestWatermarkResolution({bool emitState = false}) {
    final items = List<ChatMessage>.from(cursorPageHolder.items);
    if (items.isEmpty) return;

    // Phase 1: Newest (index 0) to oldest scan - register senders
    for (final msg in items) {
      final senderId = int.tryParse(msg.senderId) ?? 0;
      if (senderId > 0) {
        if (msg.senderName.isNotEmpty || msg.senderAvatar.isNotEmpty) {
          userProfiles.putIfAbsent(
            senderId,
            () => ReadReceiptUser(
              userId: senderId,
              name: msg.senderName,
              avatarUrl: msg.senderAvatar,
            ),
          );
        }
        userLastMessageSeenID.putIfAbsent(senderId, () => msg.id);
      }
    }

    // Phase 2: Assign users exclusively to their latest message & compute tick statuses
    final updatedList = <ChatMessage>[];
    bool hasChanges = false;

    // Find the highest message ID seen by anyone other than me
    int maxOtherSeenMsgId = 0;
    final myIdInt = int.tryParse(AuthSession.tokens?.user?.id?.toString() ?? '') ?? 0;
    userLastMessageSeenID.forEach((userId, targetMsgId) {
      if (userId != myIdInt) {
        final idInt = int.tryParse(targetMsgId) ?? 0;
        if (idInt > maxOtherSeenMsgId) {
          maxOtherSeenMsgId = idInt;
        }
      }
    });

    for (final msg in items) {
      final activeReaders = <ReadReceiptUser>[];

      userLastMessageSeenID.forEach((userId, targetMsgId) {
        if (targetMsgId == msg.id && userId.toString() != msg.senderId) {
          final profile = userProfiles[userId] ??
              ReadReceiptUser(
                userId: userId,
                name: '',
                avatarUrl: '',
              );
          activeReaders.add(profile);
        }
      });

      final currentMsgId = int.tryParse(msg.id) ?? 0;
      final computedSeen = msg.isMine && currentMsgId > 0 && maxOtherSeenMsgId > 0 && currentMsgId <= maxOtherSeenMsgId;
      final computedDelivered = msg.isMine && (isGroup || msg.isDelivered || computedSeen);

      final finalSeen = msg.isSeen || computedSeen;
      final finalDelivered = msg.isDelivered || computedDelivered || finalSeen;

      final hasDiff = activeReaders.length != msg.readBy.length ||
          !activeReaders.every((a) => msg.readBy.any((b) => b.userId == a.userId)) ||
          msg.isSeen != finalSeen ||
          msg.isDelivered != finalDelivered;

      if (hasDiff) {
        hasChanges = true;
        updatedList.add(msg.copyWith(
          readBy: activeReaders,
          readCount: activeReaders.length,
          isSeen: finalSeen,
          isDelivered: finalDelivered,
        ));
      } else {
        updatedList.add(msg);
      }
    }

    if (hasChanges) {
      replaceLocalItems(updatedList, emitState: emitState);
    }
  }

  @override
  void clearLocalItems({bool resetPaginationState = false}) {
    userLastMessageSeenID.clear();
    userProfiles.clear();
    super.clearLocalItems(resetPaginationState: resetPaginationState);
  }
}
