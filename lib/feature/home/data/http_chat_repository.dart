import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:whatsapp_flutter_go/core/db/local_cache/base_cache_repository.dart';
import 'package:whatsapp_flutter_go/core/db/network/chat_endpoints.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';

import '../model/chat_message.dart';
import '../model/chat_user.dart';
import '../model/conversation.dart';
import 'chat_repository.dart';

/// Conversations, message history, and users list come from the real chat backend.
class HttpChatRepository extends BaseCachedRepository implements ChatRepository {
  const HttpChatRepository({
    super.cache,
    super.dataApi,
  });

  static Future<void> _writeQueue = Future.value();
  static int _conversationWriteRevision = 0;
  static int _conversationCommittedRevision = 0;

  @visibleForTesting
  static void resetWriteSequencingForTesting() {
    _writeQueue = Future.value();
    _conversationWriteRevision = 0;
    _conversationCommittedRevision = 0;
  }

  @override
  Future<List<Conversation>> getConversations() async {
    final capturedUserScope = cache.resolveCurrentUserScope();
    final capturedEpoch = cache.sessionEpoch;
    final writeRevision = ++_conversationWriteRevision;

    final response = await fetch(
      ChatEndpoints.conversations(),
      null,
    );
    final map = _asMap(response);
    if (map != null) {
      unawaited(
        _writeQueue = _writeQueue.then((_) async {
          if (writeRevision < _conversationCommittedRevision) {
            log(
              'Stale getConversations write skipped: revision $writeRevision < committed $_conversationCommittedRevision',
              name: 'HttpChatRepository',
            );
            return;
          }
          if (cache.sessionEpoch != capturedEpoch ||
              cache.resolveCurrentUserScope() != capturedUserScope) {
            log(
              'getConversations write skipped: user or session changed',
              name: 'HttpChatRepository',
            );
            return;
          }
          await cache.cacheResponse(
            endpoint: ChatEndpoints.conversations(),
            data: map,
            targetUserScope: capturedUserScope,
            sessionEpoch: capturedEpoch,
            writeRevision: writeRevision,
          );
          _conversationCommittedRevision = writeRevision;
        }).catchError((_) {}),
      );
    }
    return _parseConversations(map);
  }

  @override
  Stream<List<Conversation>> watchConversations({
    Duration? maxStale,
    bool? invalidCache,
    Duration maxAge = const Duration(minutes: 5),
  }) {
    return cachedStream<List<Conversation>>(
      endpoint: ChatEndpoints.conversations(),
      fromJson: (json) => _parseConversations(json),
      maxAge: maxAge,
      maxStale: maxStale,
      invalidCache: invalidCache,
    );
  }

  @override
  Future<void> persistConversations(List<Conversation> conversations) {
    final capturedUserScope = cache.resolveCurrentUserScope();
    final capturedEpoch = cache.sessionEpoch;
    final writeRevision = ++_conversationWriteRevision;

    return _writeQueue = _writeQueue.then((_) async {
      if (writeRevision < _conversationCommittedRevision) {
        log(
          'Stale persistConversations write skipped: revision $writeRevision < committed $_conversationCommittedRevision',
          name: 'HttpChatRepository',
        );
        return;
      }
      if (cache.sessionEpoch != capturedEpoch ||
          cache.resolveCurrentUserScope() != capturedUserScope) {
        log(
          'persistConversations write skipped: user or session changed',
          name: 'HttpChatRepository',
        );
        return;
      }

      try {
        await cache.cacheResponse(
          endpoint: ChatEndpoints.conversations(),
          data: {
            'conversations': conversations.map((c) => c.toJson()).toList(),
          },
          targetUserScope: capturedUserScope,
          sessionEpoch: capturedEpoch,
          writeRevision: writeRevision,
        );
        _conversationCommittedRevision = writeRevision;
      } catch (e, st) {
        log(
          'Failed to persist conversations: $e',
          name: 'HttpChatRepository',
          stackTrace: st,
        );
      }
    }).catchError((_) {});
  }

  List<Conversation> _parseConversations(Map<String, dynamic>? map) {
    final list = map?['conversations'];
    if (list is! List) return const [];

    final conversations = list
        .whereType<Map>()
        .map((json) => Conversation.fromJson(Map<String, dynamic>.from(json)))
        .toList();

    // Don't trust the backend's own ordering — sort by recency here too, so
    // a fresh fetch always agrees with where the socket's `new_message`
    // handling would have moved a conversation to.
    conversations.sort(
      (a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(
        a.lastMessageAt ?? a.createdAt,
      ),
    );
    return conversations;
  }

  @override
  Future<List<ChatUser>> getAllUsers() async {
    final response = await dataApi.getResponse(
      url: ChatEndpoints.users(),
    );
    final list = _asMap(response)?['users'];
    if (list is! List) return const [];

    return list
        .whereType<Map>()
        .map((json) => ChatUser.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  @override
  Future<String> getOrCreateDirectConversation(int targetUserId) async {
    final response = await dataApi.postResponse(
      url: ChatEndpoints.directConversation(),
      data: {'target_user_id': targetUserId},
    );
    final map = _asMap(response);
    final convId = map?['conversation_id']?.toString();
    if (convId == null || convId.isEmpty) {
      throw Exception('Failed to get conversation ID from server');
    }
    return convId;
  }

  @override
  Future<CursorPaginationResponse<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 20,
    String? beforeId,
    int? sinceId,
  }) async {
    final responseMap = _asMap(
      await dataApi.getResponse(
        url: ChatEndpoints.messages(conversationId),
        query: {
          'limit': limit,
          'before_id': ?beforeId,
          'since_id': ?sinceId,
        },
      ),
    );

    final list = responseMap?['messages'];
    final myId = AuthSession.tokens?.user?.id?.toString();
    final messages = list is List
        ? list
            .whereType<Map>()
            .map(
              (json) => ChatMessage.fromJson(
                Map<String, dynamic>.from(json),
                currentUserId: myId,
              ),
            )
            .toList()
        : <ChatMessage>[];

    final nextBeforeId = responseMap?['next_before_id'];
    final rawNextSinceId = responseMap?['next_since_id'];
    final nextSinceId = rawNextSinceId is int
        ? rawNextSinceId
        : (rawNextSinceId != null
            ? int.tryParse(rawNextSinceId.toString())
            : null);

    final hasMore = responseMap?['has_more'] as bool? ?? (nextBeforeId != null);
    final nextCursorStr =
        (hasMore && nextBeforeId != null && nextBeforeId != 0 && nextBeforeId != '0')
            ? nextBeforeId.toString()
            : null;

    final watermarks = responseMap?['watermarks'];

    return CursorPaginationResponse(
      current: beforeId ?? sinceId?.toString(),
      data: messages,
      fromJsonFactory: ChatMessage.fromJson,
      toJsonFactory: (model) => model.toJson(),
      nextCursor: nextCursorStr,
      hasMore: hasMore,
      nextSinceId: nextSinceId,
      extra: {
        if (watermarks is Map) 'watermarks': watermarks,
        'next_since_id': ?nextSinceId,
        'has_more': hasMore,
      },
    );
  }

  Map<String, dynamic>? _asMap(dynamic value) => switch (value) {
    final Map<String, dynamic> value => value,
    final Map value => Map<String, dynamic>.from(value),
    _ => null,
  };
}
