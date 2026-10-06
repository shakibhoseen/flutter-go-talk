import 'dart:developer';

import 'package:either_dart/either.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/local_sync_cursor_pagination_bloc.dart';

import '../../../core/session/auth_session.dart';
import '../../home/data/http_chat_repository.dart';
import '../../home/model/chat_message.dart';

class InboxMessageListCursorBloc
    extends LocalSyncCursorPaginationBloc<ChatMessage> {
  final HttpChatRepository repository;
  final pageSize = 20;
  final String conversationId;
  final bool isGroup;

  InboxMessageListCursorBloc({
    required this.conversationId,
    this.isGroup = false,
    HttpChatRepository? repository,
  })  : repository = repository ?? const HttpChatRepository(),
        super(InitialState());

  @override
  String itemIdentity(ChatMessage item) => item.id;

  @override
  ChatMessage mergeItem(ChatMessage existing, ChatMessage incoming) {
    // Monotonic status merge: newer delivery or seen status must never be
    // downgraded by an older/stale status from another source (HTTP delta vs WebSocket).
    final mergedSeen = existing.isSeen || incoming.isSeen;
    final mergedDelivered = existing.isDelivered || incoming.isDelivered || mergedSeen;

    final mergedReadBy = _mergeReadBy(existing.readBy, incoming.readBy);
    final baseCount = existing.readCount > incoming.readCount
        ? existing.readCount
        : incoming.readCount;
    final mergedReadCount =
        mergedReadBy.length > baseCount ? mergedReadBy.length : baseCount;

    return incoming.copyWith(
      isDelivered: mergedDelivered,
      isSeen: mergedSeen,
      readCount: mergedReadCount,
      readBy: mergedReadBy,
    );
  }

  /// Merges two readBy user lists, preserving existing ordering and deduplicating by userId.
  List<ReadReceiptUser> _mergeReadBy(
    List<ReadReceiptUser> existing,
    List<ReadReceiptUser> incoming,
  ) {
    if (existing.isEmpty) return incoming;
    if (incoming.isEmpty) return existing;

    final merged = <ReadReceiptUser>[];
    final userIndexMap = <int, int>{};

    for (final user in existing) {
      userIndexMap[user.userId] = merged.length;
      merged.add(user);
    }

    for (final inc in incoming) {
      final existingIndex = userIndexMap[inc.userId];
      if (existingIndex == null) {
        userIndexMap[inc.userId] = merged.length;
        merged.add(inc);
      } else {
        final current = merged[existingIndex];
        if ((current.name.isEmpty && inc.name.isNotEmpty) ||
            (current.avatarUrl.isEmpty && inc.avatarUrl.isNotEmpty)) {
          merged[existingIndex] = current.copyWith(
            name: current.name.isNotEmpty ? current.name : inc.name,
            avatarUrl: current.avatarUrl.isNotEmpty ? current.avatarUrl : inc.avatarUrl,
          );
        }
      }
    }

    return merged;
  }

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
          !isGroup && maxOtherSeenId > 0 && messageId <= maxOtherSeenId;

      final finalSeen = message.isSeen || computedSeen;

      final finalDelivered = message.isDelivered || finalSeen;

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

  /// Returns the highest message ID currently loaded in memory.
  int? get latestMessageId {
    int? maxId;
    for (final item in cursorPageHolder.items) {
      final id = int.tryParse(item.id);
      if (id != null && id > 0) {
        if (maxId == null || id > maxId) {
          maxId = id;
        }
      }
    }
    return maxId;
  }

  bool _isSyncingMissedMessages = false;
  bool get isSyncingMissedMessages => _isSyncingMissedMessages;

  /// Recovers all missed messages and watermarks after [latestMessageId] using
  /// forward delta sync. If the inbox is empty, falls back to normal initial load.
  /// Returns [true] if the delta sync completed successfully across all pages,
  /// or [false] if the sync was partial, failed, non-advancing, or could not run.
  Future<bool> syncMissedMessages() async {
    if (_isSyncingMissedMessages) {
      return false;
    }

    final startSinceId = latestMessageId;
    if (startSinceId == null) {
      // If no messages are currently loaded, perform regular initial load
      execute(pageFromStart: true);
      return false;
    }

    _isSyncingMissedMessages = true;
    try {
      int? currentSinceId = startSinceId;
      bool hasMore = true;

      while (hasMore && currentSinceId != null) {
        final response = await repository.getMessages(
          conversationId,
          limit: 50,
          sinceId: currentSinceId,
        );

        // 1. Monotonically update watermarks from this page
        extractWaterMark(response.extra?['watermarks']);

        // 2. Upsert incoming missed messages (deduped via itemIdentity)
        final incoming = response.data ?? [];
        if (incoming.isNotEmpty) {
          for (final msg in incoming) {
            final senderId = int.tryParse(msg.senderId) ?? 0;
            if (senderId > 0 &&
                !userProfiles.containsKey(senderId) &&
                (msg.senderName.isNotEmpty || msg.senderAvatar.isNotEmpty)) {
              userProfiles[senderId] = ReadReceiptUser(
                userId: senderId,
                name: msg.senderName,
                avatarUrl: msg.senderAvatar,
              );
            }
            upsertLocalItem(msg, insertAtStart: true, emitState: false);
          }
        }

        hasMore = response.hasMore ?? false;
        final nextId = response.nextSinceId;

        // Break if there is no next cursor or no forward progress to prevent infinite loops
        if (nextId == null || nextId <= currentSinceId) {
          if (hasMore) {
            if (nextId == null) {
              log(
                'has_more=true but next_since_id=null from backend delta sync',
                name: 'InboxMessageListCursorBloc',
              );
            } else {
              log(
                'has_more=true but next_since_id ($nextId) did not advance beyond current ($currentSinceId)',
                name: 'InboxMessageListCursorBloc',
              );
            }
            return false;
          }
          break;
        }
        currentSinceId = nextId;
      }

      // Ensure local messages remain sorted strictly newest (index 0) -> oldest
      cursorPageHolder.items.sort((a, b) {
        final idA = int.tryParse(a.id) ?? 0;
        final idB = int.tryParse(b.id) ?? 0;
        return idB.compareTo(idA);
      });

      // 3. Apply watermarks to all loaded messages and emit state once
      _applyLatestWatermarkResolution(
        messages: cursorPageHolder.items,
        emitState: true,
      );

      return true;
    } catch (e, stackTrace) {
      log(
        'syncMissedMessages error: $e',
        name: 'InboxMessageListCursorBloc',
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _isSyncingMissedMessages = false;
    }
  }
}
