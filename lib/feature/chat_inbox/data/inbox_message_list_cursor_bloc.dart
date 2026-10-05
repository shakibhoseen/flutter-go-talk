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

  final Map<int, int> userLastMessageSeenID = {};
  final Map<int, ReadReceiptUser> userProfiles = {};

  void execute({bool? pageFromStart}) {
    add(
      FetchDataWithQueryEvent(
        query: {},
        clearPageWithNewData: pageFromStart ?? false,
      ),
    );
  }

  @override
  void doActionBeforeEmitSuccessWithPaginationState(
    SuccessWithPaginationState<CursorPaginationResponse<ChatMessage>> state,
  ) {
    super.doActionBeforeEmitSuccessWithPaginationState(state);

    extractWaterMark(state.data.extra?['watermarks']);

    _applyLatestWatermarkResolution(
      messages: cursorPageHolder.items,
      emitState: false,
    );
  }


  void extractWaterMark(dynamic watermarks) {
    if (watermarks is! Map) {
      return;
    }

    for (final entry in watermarks.entries) {
      final messageId = int.tryParse(entry.key.toString());

      if (messageId == null || messageId <= 0) {
        continue;
      }

      final watermarkData = entry.value;

      if (watermarkData is! Map) {
        continue;
      }

      final users = watermarkData['users'];

      if (users is! List) {
        continue;
      }

      for (final user in users) {
        if (user is! Map) {
          continue;
        }

        final profile = ReadReceiptUser.fromJson(
          Map<String, dynamic>.from(user),
        );

        updateMemberWatermark(
          userId: profile.userId,
          messageId: messageId,
          profile: profile,
        );
      }
    }
  }

  /// Updates one user's watermark.
  ///
  /// A watermark can only move forward:
  ///
  /// 135 -> 140  ✅
  /// 140 -> 135  ❌
  void updateMemberWatermark({
    required int userId,
    required int messageId,
    ReadReceiptUser? profile,
  }) {
    if (messageId <= 0) {
      return;
    }

    final oldMessageId = userLastMessageSeenID[userId] ?? 0;

    if (messageId > oldMessageId) {
      userLastMessageSeenID[userId] = messageId;
    }

    if (profile != null) {
      userProfiles[userId] = profile;
    }
  }

  // ---------------------------------------------------------------------------
  // Seen calculation
  // ---------------------------------------------------------------------------

  /// Highest message ID seen by any user other than the current user.
  ///
  /// Example:
  ///
  /// Me -> 138
  /// B  -> 135
  /// C  -> 125
  ///
  /// returns 135.
  int get maxOtherSeenMessageId {
    final currentUserId =
        int.tryParse(AuthSession.tokens?.user?.id?.toString() ?? '') ?? 0;

    var maxSeenId = 0;

    for (final entry in userLastMessageSeenID.entries) {
      if (entry.key == currentUserId) {
        continue;
      }

      if (entry.value > maxSeenId) {
        maxSeenId = entry.value;
      }
    }

    return maxSeenId;
  }



  void _applyLatestWatermarkResolution({
    required List<ChatMessage> messages,
    bool emitState = false,
  }) {
    final maxOtherSeenId = maxOtherSeenMessageId;

    final updatedMessages = messages.map((message) {
      if (!message.isMine) {
        return message;
      }

      final messageId = int.tryParse(message.id);

      if (messageId == null) {
        return message;
      }

      final computedSeen =
          maxOtherSeenId > 0 && messageId <= maxOtherSeenId;

      final finalSeen = message.isSeen || computedSeen;

      final finalDelivered =
          message.isDelivered || finalSeen;

      if (message.isSeen == finalSeen &&
          message.isDelivered == finalDelivered) {
        return message;
      }

      return message.copyWith(
        isSeen: finalSeen,
        isDelivered: finalDelivered,
      );
    }).toList();

    replaceLocalItems(
      updatedMessages,
      emitState: emitState,
    );
  }

  // ---------------------------------------------------------------------------
  // Read-receipt profile bubbles
  // ---------------------------------------------------------------------------

  /// Returns users whose exact watermark is this message.
  ///
  /// Example:
  ///
  /// B -> 135
  /// C -> 125
  ///
  /// getWatermarkUsers("135") -> [B]
  /// getWatermarkUsers("134") -> []
  List<ReadReceiptUser> getWatermarkUsers(String messageId) {
    final targetMessageId = int.tryParse(messageId);

    if (targetMessageId == null) {
      return [];
    }

    final users = <ReadReceiptUser>[];

    for (final entry in userLastMessageSeenID.entries) {
      if (entry.value != targetMessageId) {
        continue;
      }

      final profile = userProfiles[entry.key];

      if (profile != null) {
        users.add(profile);
      }
    }

    return users;
  }

  int getWatermarkCount(String messageId) {
    return getWatermarkUsers(messageId).length;
  }

  // ---------------------------------------------------------------------------
  // WebSocket watermark event
  // ---------------------------------------------------------------------------

  void handleMemberWatermark({
    required int userId,
    required int messageId,
    ReadReceiptUser? profile,
  }) {
    updateMemberWatermark(
      userId: userId,
      messageId: messageId,
      profile: profile,
    );

    // Unlike pagination, WebSocket has no outer pagination success state
    // that will emit this change for us.
    _applyLatestWatermarkResolution(
      messages: cursorPageHolder.items,
      emitState: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Clear
  // ---------------------------------------------------------------------------

  @override
  void clearLocalItems({bool resetPaginationState = false}) {
    userLastMessageSeenID.clear();
    userProfiles.clear();
    super.clearLocalItems(resetPaginationState: resetPaginationState);
  }


  void handleNewMessage({
    required ChatMessage message,
    ReadReceiptUser? profile,
  }) {
    upsertLocalItem(message, emitState: false);

    final senderId = int.tryParse(message.senderId) ?? 0;
    final messageId = int.tryParse(message.id) ?? 0;

    if (senderId > 0 && messageId > 0) {
      updateMemberWatermark(
        userId: senderId,
        messageId: messageId,
        profile: profile,
      );
    }

    _applyLatestWatermarkResolution(
      messages: cursorPageHolder.items,
      emitState: true,
    );
  }
}
