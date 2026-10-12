import 'dart:async';
import 'dart:developer';

import 'package:either_dart/either.dart';
import 'package:flutter/foundation.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/local_sync_cursor_pagination_bloc.dart';

import '../../../core/db/local_cache/chat_message_cache.dart';
import '../../../core/db/network/socket/chat_socket_service.dart';
import '../../../core/session/auth_session.dart';
import '../../home/data/http_chat_repository.dart';
import '../../home/model/chat_message.dart';
import 'chat_seen_ack_manager.dart';
import 'outbox/client_message_id_generator.dart';
import 'outbox/local_outbox_storage.dart';
import 'outbox/pending_outbox_message.dart';

class InboxMessageListCursorBloc
    extends LocalSyncCursorPaginationBloc<ChatMessage> {
  final HttpChatRepository repository;
  final pageSize = 20;
  final String conversationId;
  final bool isGroup;
  final Set<int>? groupMemberIds;
  final LocalOutboxStorage outboxStorage;
  final ChatMessageCache messageCache;

  InboxMessageListCursorBloc({
    required this.conversationId,
    this.isGroup = false,
    this.groupMemberIds,
    HttpChatRepository? repository,
    LocalOutboxStorage? outboxStorage,
    ChatMessageCache? messageCache,
  })  : repository = repository ?? const HttpChatRepository(),
        outboxStorage = outboxStorage ?? SharedPreferencesOutboxStorage(),
        messageCache = messageCache ?? ChatMessageCache(),
        super(InitialState());

  @override
  String itemIdentity(ChatMessage item) {
    final clientId = item.clientMessageId;

    if (clientId != null && clientId.isNotEmpty) {
      return clientId;
    }

    return item.id;
  }

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
      id: incoming.id.isNotEmpty ? incoming.id : existing.id,
      clientMessageId: incoming.clientMessageId ?? existing.clientMessageId,
      isMine: incoming.isMine || existing.isMine,
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
    try {
      final response = await repository.getMessages(
        conversationId,
        limit: pageSize,
        beforeId: nextCursor,
      );

      setCursor(model: response);
      return Left(response);
    } catch (e) {
      final wasInitialLoading = _isInitialLoading;
      _isInitialLoading = false;
      if (cursorPageHolder.items.isNotEmpty) {
        _hasInitialLoaded = true;
      }
      if (wasInitialLoading) {
        onInitialLoadCompleted?.call();
      }
      if (cursorPageHolder.items.isNotEmpty) {
        emitCurrentLocalData(hasCleared: false);
      }
      rethrow;
    }
  }

  final Map<int, int> userLastMessageSeenID = {};
  final Map<int, ReadReceiptUser> userProfiles = {};

  VoidCallback? onInitialLoadCompleted;

  bool _isInitialLoading = false;
  bool _hasInitialLoaded = false;
  int? _currentSessionEpoch;
  String? _currentUserScope;
  Future<void>? _initialHydrationFuture;

  @visibleForTesting
  Future<void>? get initialHydrationFuture => _initialHydrationFuture;

  bool get isInitialLoading => _isInitialLoading;
  bool get hasInitialLoaded => _hasInitialLoaded;

  void execute({bool? pageFromStart}) {
    final isInitial =
        !_hasInitialLoaded && (cursorPageHolder.items.isEmpty || (pageFromStart ?? false));

    if (isInitial) {
      _isInitialLoading = true;
      _initialHydrationFuture = _executeInitialHydrationAndFetch(
        pageFromStart: pageFromStart ?? false,
      );
      return;
    }

    add(
      FetchDataWithQueryEvent(
        query: {},
        clearPageWithNewData: pageFromStart ?? false,
      ),
    );
  }

  Future<void> _executeInitialHydrationAndFetch({
    required bool pageFromStart,
  }) async {
    _currentSessionEpoch = messageCache.sessionEpoch;
    _currentUserScope = messageCache.resolveCurrentUserScope();

    try {
      // 1. Read persisted confirmed messages from local storage
      final cached = await messageCache.getMessages(
        conversationId: conversationId,
        targetUserScope: _currentUserScope,
      );

      // 2. Load pending outgoing messages from LocalOutboxStorage
      final pendingOutbox = await outboxStorage.getMessagesForConversation(
        conversationId,
        targetUserScope: _currentUserScope,
      );

      // 3. Merge both without duplicates and emit the cached view promptly
      if ((cached != null && cached.messages.isNotEmpty) || pendingOutbox.isNotEmpty) {
        _hydrateLocalSnapshot(
          cachedMessages: cached?.messages ?? [],
          watermarks: cached?.watermarks,
          pendingOutbox: pendingOutbox,
          userScope: _currentUserScope ?? '',
        );
      }
    } catch (e, st) {
      log('Initial cache hydration error: $e', name: 'InboxMessageListCursorBloc', stackTrace: st);
    }

    // 4. Start the existing server history request
    add(
      FetchDataWithQueryEvent(
        query: {},
        clearPageWithNewData: false,
      ),
    );
  }

  void _hydrateLocalSnapshot({
    required List<ChatMessage> cachedMessages,
    dynamic watermarks,
    required List<PendingOutboxMessage> pendingOutbox,
    required String userScope,
  }) {
    final pendingMessages = pendingOutbox.map((p) => ChatMessage(
      id: '',
      clientMessageId: p.clientMessageId,
      senderId: p.senderId.isNotEmpty ? p.senderId : userScope,
      receiverId: p.conversationId,
      message: p.content,
      sentAt: p.createdAt,
      messageType: p.messageType,
      isMine: true,
      isDelivered: false,
      isSeen: false,
      timeStamp: TimeStamp.fromDatePublish(p.createdAt.millisecondsSinceEpoch),
    )).toList();

    final confirmedClientIds = cachedMessages
        .map((m) => m.clientMessageId)
        .where((id) => id != null && id.isNotEmpty)
        .toSet();

    for (final p in pendingMessages) {
      if (confirmedClientIds.contains(p.clientMessageId)) {
        unawaited(outboxStorage.remove(p.clientMessageId!));
      }
    }

    final activePending = pendingMessages
        .where((p) => !confirmedClientIds.contains(p.clientMessageId))
        .toList();

    activePending.sort((a, b) => b.sentAt.compareTo(a.sentAt));

    final merged = <ChatMessage>[
      ...activePending,
      ...cachedMessages,
    ];

    extractWaterMark(watermarks);

    cursorPageHolder.items = List<ChatMessage>.from(merged);

    saveResponse = CursorPaginationResponse<ChatMessage>(
      data: List<ChatMessage>.from(merged),
      hasMore: false,
      fromJsonFactory: ChatMessage.fromJson,
      toJsonFactory: (m) => m.toJson(),
      extra: {
        'watermarks': ?watermarks,
      },
    );

    _applyLatestWatermarkResolution(
      messages: cursorPageHolder.items,
      emitState: false,
    );

    emitCurrentLocalData(hasCleared: false);
  }

  @override
  void doActionBeforeEmitSuccessWithPaginationState(
    SuccessWithPaginationState<CursorPaginationResponse<ChatMessage>> state,
  ) {
    final response = state.data;
    final incoming = response.data ?? <ChatMessage>[];
    final existing = cursorPageHolder.items;

    // 1. Reconcile outbox for incoming server-confirmed items
    _reconcileOutboxFromIncoming(incoming);

    final incomingClientIds = incoming
        .map((m) => m.clientMessageId)
        .where((id) => id != null && id.isNotEmpty)
        .toSet();

    // 2. Identify unresolved pending outbox messages in local state
    final unresolvedPending = existing.where((msg) {
      final isPending = msg.isMine &&
          (msg.id.isEmpty || msg.id == '0') &&
          msg.clientMessageId != null &&
          msg.clientMessageId!.isNotEmpty;
      return isPending && !incomingClientIds.contains(msg.clientMessageId);
    }).toList();

    // 3. Merge confirmed messages from existing (cached + live WebSocket) and incoming (HTTP page)
    final existingConfirmed = existing
        .where((m) => m.id.isNotEmpty && m.id != '0')
        .toList();

    final incomingConfirmed = incoming
        .where((m) => m.id.isNotEmpty && m.id != '0')
        .toList();

    final mergedConfirmed = _mergeConfirmedHistory(
      existingConfirmed: existingConfirmed,
      incomingConfirmed: incomingConfirmed,
    );

    // 4. Unresolved pending messages always sit at the very top (index 0..k), newest first
    unresolvedPending.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    final finalMerged = <ChatMessage>[
      ...unresolvedPending,
      ...mergedConfirmed,
    ];

    // 5. Update holders and response state
    cursorPageHolder.items = List<ChatMessage>.from(finalMerged);
    cursorPageHolder.nextCursor = nextCursor;
    response.data = List<ChatMessage>.from(finalMerged);
    saveResponse = response;

    extractWaterMark(state.data.extra?['watermarks']);

    _applyLatestWatermarkResolution(
      messages: cursorPageHolder.items,
      emitState: false,
    );

    _persistConfirmedMessages(state.data.extra?['watermarks']);

    final wasInitialLoading = _isInitialLoading;
    _isInitialLoading = false;
    _hasInitialLoaded = true;

    if (wasInitialLoading) {
      onInitialLoadCompleted?.call();
    }
  }

  List<ChatMessage> _mergeConfirmedHistory({
    required List<ChatMessage> existingConfirmed,
    required List<ChatMessage> incomingConfirmed,
  }) {
    if (incomingConfirmed.isEmpty) {
      return List<ChatMessage>.from(existingConfirmed);
    }
    if (existingConfirmed.isEmpty) {
      return List<ChatMessage>.from(incomingConfirmed);
    }

    // 1. Map existing items by identity for fast lookup
    final existingByIdentity = <String, ChatMessage>{};
    for (final e in existingConfirmed) {
      existingByIdentity[itemIdentity(e)] = e;
    }

    // 2. Identify existing items that are NOT present in incoming
    final incomingIdentities =
        incomingConfirmed.map((m) => itemIdentity(m)).toSet();
    final notInIncoming = existingConfirmed
        .where((e) => !incomingIdentities.contains(itemIdentity(e)))
        .toList();

    // 3. For items in incoming, merge monotonic state from existing if found
    final mergedIncoming = incomingConfirmed.map((inc) {
      final existing = existingByIdentity[itemIdentity(inc)];
      if (existing != null) {
        return mergeItem(existing, inc);
      }
      return inc;
    }).toList();

    // 4. Combine all confirmed messages (incoming + local confirmed not in incoming)
    final combinedConfirmed = <ChatMessage>[
      ...mergedIncoming,
      ...notInIncoming,
    ];

    // 5. Canonical descending sort (ORDER BY id DESC, matching Go backend contract),
    // falling back to sentAt descending.
    combinedConfirmed.sort(_compareCanonicalDescending);

    return combinedConfirmed;
  }

  int _compareCanonicalDescending(ChatMessage a, ChatMessage b) {
    final aId = int.tryParse(a.id);
    final bId = int.tryParse(b.id);
    if (aId != null && bId != null) {
      if (aId != bId) {
        return bId.compareTo(aId); // Higher ID first (id DESC)
      }
    }
    final sentAtCompare = b.sentAt.compareTo(a.sentAt);
    if (sentAtCompare != 0) {
      return sentAtCompare;
    }
    return b.id.compareTo(a.id);
  }

  /// Exports in-memory watermark state to a JSON map compatible with the
  /// backend's watermarks structure (`{ "<msgId>": { "users": [...], "count": N } }`).
  Map<String, dynamic> exportWatermarksJson() {
    final result = <String, dynamic>{};
    for (final entry in userLastMessageSeenID.entries) {
      final userId = entry.key;
      final msgId = entry.value;
      if (msgId <= 0) continue;
      final msgKey = msgId.toString();
      final profile = userProfiles[userId] ??
          ReadReceiptUser(userId: userId, name: '', avatarUrl: '');
      final existingGroup = result[msgKey];
      if (existingGroup is Map<String, dynamic>) {
        final users = existingGroup['users'] as List<dynamic>;
        users.add(profile.toJson());
        existingGroup['count'] = users.length;
      } else {
        result[msgKey] = {
          'users': [profile.toJson()],
          'count': 1,
        };
      }
    }
    return result;
  }

  void _persistConfirmedMessages([dynamic watermarks]) {
    final confirmed = cursorPageHolder.items
        .where((m) => m.id.isNotEmpty && m.id != '0')
        .take(50)
        .toList();

    if (confirmed.isNotEmpty) {
      final exported = exportWatermarksJson();
      final effectiveWatermarks =
          watermarks ?? (exported.isNotEmpty ? exported : null);
      unawaited(
        messageCache.saveMessages(
          conversationId: conversationId,
          messages: confirmed,
          watermarks: effectiveWatermarks,
          targetUserScope: _currentUserScope ?? messageCache.resolveCurrentUserScope(),
          sessionEpoch: _currentSessionEpoch ?? messageCache.sessionEpoch,
        ),
      );
    }
  }

  void _reconcileOutboxFromIncoming(List<ChatMessage>? incoming) {
    if (incoming == null || incoming.isEmpty) return;

    for (final msg in incoming) {
      final clientMsgId = msg.clientMessageId;
      if (msg.isMine && clientMsgId != null && clientMsgId.trim().isNotEmpty) {
        outboxStorage.remove(clientMsgId);
      }
    }
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

        final currentUserId =
            int.tryParse(_currentUserScope ?? AuthSession.tokens?.user?.id?.toString() ?? '') ?? 0;
        if (currentUserId > 0 && profile.userId == currentUserId) {
          unawaited(
            ChatSeenAckManager.instance.confirmServerWatermark(
              conversationId: conversationId,
              serverMessageId: messageId,
            ),
          );
        }
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
    final currentUserId =
        int.tryParse(AuthSession.tokens?.user?.id?.toString() ?? '') ?? 0;

    final otherGroupMembers =
        groupMemberIds != null && groupMemberIds!.isNotEmpty
            ? groupMemberIds!.where((id) => id != currentUserId).toSet()
            : null;

    final updatedMessages = messages.map((message) {
      if (!message.isMine) {
        return message;
      }

      final messageId = int.tryParse(message.id);

      if (messageId == null) {
        return message;
      }

      bool computedSeen;
      if (!isGroup) {
        computedSeen = maxOtherSeenId > 0 && messageId <= maxOtherSeenId;
      } else if (otherGroupMembers != null && otherGroupMembers.isNotEmpty) {
        computedSeen = otherGroupMembers.every(
          (mId) => (userLastMessageSeenID[mId] ?? 0) >= messageId,
        );
      } else {
        computedSeen = false;
      }

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

    _persistConfirmedMessages();
  }

  /// Reconciles incoming delivery or seen status from WebSocket `status_updated`
  /// monotonically and persists updated items to local cache.
  bool handleStatusUpdated({
    required String? statusMessageId,
    required String? status,
  }) {
    if (statusMessageId == null) return false;
    final targetId = int.tryParse(statusMessageId) ?? 0;
    final isSeenEvent = status == 'seen';
    final isDeliveredEvent = status == 'delivered';
    if (!isSeenEvent && !isDeliveredEvent) return false;

    final items = cursorPageHolder.items;
    if (items.isEmpty) return false;

    var changed = false;
    final updated = items.map((item) {
      if (!item.isMine) return item;
      final currentId = int.tryParse(item.id) ?? 0;
      if (currentId <= 0 || currentId > targetId) return item;

      // Monotonicity: seen implies delivered. Once seen, cannot be downgraded.
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
      replaceLocalItems(updated, emitState: true);
      _persistConfirmedMessages();
    }
    return changed;
  }

  // ---------------------------------------------------------------------------
  // Clear
  // ---------------------------------------------------------------------------

  @override
  void clearLocalItems({bool resetPaginationState = false}) {
    userLastMessageSeenID.clear();
    userProfiles.clear();
    _isInitialLoading = false;
    _hasInitialLoaded = false;
    _initialHydrationFuture = null;
    super.clearLocalItems(resetPaginationState: resetPaginationState);
  }


  /// Reconciles a server-confirmed message (live WebSocket echo or delta-sync)
  /// with any matching local optimistic message using [clientMessageId].
  ///
  /// Steps:
  /// A. Identifies [serverMessage.clientMessageId].
  /// B. Merges/upserts the message into local state via [itemIdentity] and [mergeItem].
  /// C. If the message belongs to this client and has a valid [clientMessageId],
  ///    removes the durable record from [outboxStorage].
  Future<void> reconcileServerMessage(
    ChatMessage serverMessage, {
    bool emitState = true,
  }) async {
    final clientMessageId = serverMessage.clientMessageId;

    // Step B: Reconcile in local item list using itemIdentity + mergeItem + upsertLocalItem
    upsertLocalItem(serverMessage, emitState: emitState);

    // Step C: Remove outbox record after server confirmation
    if (serverMessage.isMine &&
        clientMessageId != null &&
        clientMessageId.isNotEmpty) {
      await outboxStorage.remove(clientMessageId);
    }
  }

  /// Generates a single logical [clientMessageId], persists it to durable [outboxStorage]
  /// BEFORE transmission, adds the optimistic message locally, and transmits over
  /// WebSocket if connected.
  Future<ChatMessage> sendOutgoingMessage({
    required String content,
    String? clientMessageId,
    String messageType = 'text',
    String? currentUserId,
  }) async {
    final effectiveClientMessageId =
        clientMessageId ?? ClientMessageIdGenerator.generate();
    final now = DateTime.now();

    final optimisticMessage = ChatMessage(
      id: '',
      clientMessageId: effectiveClientMessageId,
      senderId: currentUserId ?? '',
      receiverId: conversationId,
      message: content,
      sentAt: now,
      messageType: messageType,
      isMine: true,
      isDelivered: false,
      isSeen: false,
      timeStamp: TimeStamp.fromDatePublish(now.millisecondsSinceEpoch),
    );

    final effectiveSenderId = (currentUserId != null && currentUserId.isNotEmpty)
        ? currentUserId
        : (_currentUserScope ?? messageCache.resolveCurrentUserScope());

    // 1. Persist to outbox BEFORE network transmission
    final pendingOutbox = PendingOutboxMessage(
      clientMessageId: effectiveClientMessageId,
      conversationId: conversationId,
      content: content,
      messageType: messageType,
      createdAt: now,
      senderId: effectiveSenderId,
    );
    await outboxStorage.save(pendingOutbox);

    // 2. Ensure saveResponse is initialized so emitCurrentLocalData can emit
    if (saveResponse == null) {
      saveResponse = CursorPaginationResponse<ChatMessage>(
        data: [],
        hasMore: false,
        fromJsonFactory: ChatMessage.fromJson,
        toJsonFactory: (m) => m.toJson(),
      );
    }

    // 3. Insert optimistic message into local list and emit UI state
    upsertLocalItem(optimisticMessage, insertAtStart: true, emitState: true);

    // 4. Transmit over WebSocket only if connected; otherwise keeps pending in outbox
    if (ChatSocketService.instance.isConnected) {
      ChatSocketService.instance.sendMessage(
        conversationId: conversationId,
        content: content,
        clientMessageId: effectiveClientMessageId,
        messageType: messageType,
      );
    }

    return optimisticMessage;
  }

  Future<void> handleNewMessage({
    required ChatMessage message,
    ReadReceiptUser? profile,
  }) async {
    await reconcileServerMessage(message, emitState: false);

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

    _persistConfirmedMessages();
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
      if (!_hasInitialLoaded) {
        // If initial load has not completed yet, kick it off
        execute(pageFromStart: true);
        return false;
      }
      // If initial load already completed and latestMessageId is still null,
      // the conversation has no messages on the server yet.
      // There are no missed messages on server to sync.
      return true;
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
            await reconcileServerMessage(msg, emitState: false);
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
        final idA = int.tryParse(a.id);
        final idB = int.tryParse(b.id);
        if (idA != null && idB != null) {
          return idB.compareTo(idA);
        }
        return b.sentAt.compareTo(a.sentAt);
      });

      // 3. Apply watermarks to all loaded messages and emit state once
      _applyLatestWatermarkResolution(
        messages: cursorPageHolder.items,
        emitState: true,
      );

      _persistConfirmedMessages();

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
