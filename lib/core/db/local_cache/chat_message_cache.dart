import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../session/auth_session.dart';
import '../../../feature/home/model/chat_message.dart';
import 'hive_initializer.dart';

class ChatMessageCache {
  static final ChatMessageCache _instance = ChatMessageCache._internal();

  factory ChatMessageCache() => _instance;

  ChatMessageCache._internal();

  @visibleForTesting
  ChatMessageCache.testInstance() : this._internal();

  /// Scopes cache keys to the authenticated user ID so User A never sees
  /// User B's cached messages upon account switching.
  @visibleForTesting
  static String Function() userScopeResolver =
      () => AuthSession.tokens?.user?.id?.toString() ?? 'guest';

  int _sessionEpoch = 0;

  /// Monotonically increasing epoch counter incremented on cache clear / logout.
  int get sessionEpoch => _sessionEpoch;

  /// Resolves the current user scope.
  String resolveCurrentUserScope() => userScopeResolver();

  @visibleForTesting
  void incrementSessionEpochForTesting() => _sessionEpoch++;

  Box<String>? _box;
  Future<void>? _initFuture;
  Future<void>? _activeClearFuture;

  /// Returns a Future that completes when any in-flight cache clear has finished.
  Future<void> get pendingClearFuture => _activeClearFuture ?? Future.value();

  @visibleForTesting
  static Completer<void>? clearHoldCompleter;

  @visibleForTesting
  void resetForTesting() {
    _sessionEpoch++;
    _box = null;
    _initFuture = null;
    _activeClearFuture = null;
    clearHoldCompleter = null;
  }

  Future<void> _coordinatePendingClear() async {
    final active = _activeClearFuture;
    if (active != null) {
      await active;
    }
  }

  Future<void> _ensureInitialized() {
    if (_box != null && _box!.isOpen) return Future.value();
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    try {
      await HiveInitializer.ensureInitialized();
      _box = Hive.isBoxOpen('chat_message_history')
          ? Hive.box<String>('chat_message_history')
          : await Hive.openBox<String>('chat_message_history');
    } catch (e, st) {
      _initFuture = null;
      log('Could not initialize chat_message_history box: $e', name: 'ChatMessageCache', stackTrace: st);
    }
  }

  String _generateKey(String conversationId, String userScope) {
    return '$userScope|$conversationId';
  }

  String _generatePendingSeenKey(String conversationId, String userScope) {
    return 'pending_seen|$userScope|$conversationId';
  }

  /// Persists confirmed messages and optional watermarks for a conversation.
  /// Returns `true` if the messages were successfully written to disk, or `false`
  /// if aborted due to closed box, session epoch mismatch, or user scope mismatch.
  Future<bool> saveMessages({
    required String conversationId,
    required List<ChatMessage> messages,
    dynamic watermarks,
    bool clearWatermarks = false,
    String? targetUserScope,
    int? sessionEpoch,
  }) async {
    await _coordinatePendingClear();
    await _ensureInitialized();
    final box = _box;
    if (box == null || !box.isOpen) return false;

    final effectiveUserScope = targetUserScope ?? resolveCurrentUserScope();

    // Abort if session cleared/changed or active user scope drifted
    if (sessionEpoch != null && sessionEpoch != _sessionEpoch) {
      log(
        'Aborting saveMessages: session epoch mismatch ($sessionEpoch != $_sessionEpoch)',
        name: 'ChatMessageCache',
      );
      return false;
    }
    if (resolveCurrentUserScope() != effectiveUserScope) {
      log(
        'Aborting saveMessages: user scope mismatch ($effectiveUserScope != ${resolveCurrentUserScope()})',
        name: 'ChatMessageCache',
      );
      return false;
    }

    final key = _generateKey(conversationId, effectiveUserScope);

    dynamic effectiveWatermarks = watermarks;
    if (effectiveWatermarks == null && !clearWatermarks) {
      final existingRaw = box.get(key);
      if (existingRaw != null && existingRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(existingRaw);
          if (decoded is Map && decoded['watermarks'] != null) {
            effectiveWatermarks = decoded['watermarks'];
          }
        } catch (_) {}
      }
    }

    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'user_scope': effectiveUserScope,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'messages': messages.map((m) => m.toJson()).toList(),
      'watermarks': effectiveWatermarks,
    };

    await box.put(key, jsonEncode(payload));
    return true;
  }

  /// Persists a pending seen ACK that needs to be retried on reconnect.
  Future<void> savePendingSeenAck({
    required String conversationId,
    required int messageId,
    required int senderId,
    String? targetUserScope,
    int? sessionEpoch,
  }) async {
    await _coordinatePendingClear();
    await _ensureInitialized();
    final box = _box;
    if (box == null || !box.isOpen) return;

    final effectiveUserScope = targetUserScope ?? resolveCurrentUserScope();
    if (sessionEpoch != null && sessionEpoch != _sessionEpoch) return;
    if (resolveCurrentUserScope() != effectiveUserScope) return;

    final key = _generatePendingSeenKey(conversationId, effectiveUserScope);
    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'user_scope': effectiveUserScope,
      'message_id': messageId,
      'sender_id': senderId,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    await box.put(key, jsonEncode(payload));
  }

  /// Retrieves the pending seen ACK for a specific conversation.
  Future<({int messageId, int senderId})?> getPendingSeenAck({
    required String conversationId,
    String? targetUserScope,
  }) async {
    await _coordinatePendingClear();
    await _ensureInitialized();
    final box = _box;
    if (box == null || !box.isOpen) return null;

    final effectiveUserScope = targetUserScope ?? resolveCurrentUserScope();
    final key = _generatePendingSeenKey(conversationId, effectiveUserScope);
    final raw = box.get(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final msgId = decoded['message_id'];
      final sId = decoded['sender_id'];
      if (msgId is int) {
        return (messageId: msgId, senderId: sId is int ? sId : 0);
      }
    } catch (_) {}
    return null;
  }

  /// Retrieves all pending seen ACKs for the current user scope.
  Future<Map<String, ({int messageId, int senderId})>> getAllPendingSeenAcks({
    String? targetUserScope,
  }) async {
    await _coordinatePendingClear();
    await _ensureInitialized();
    final box = _box;
    if (box == null || !box.isOpen) return {};

    final effectiveUserScope = targetUserScope ?? resolveCurrentUserScope();
    final prefix = 'pending_seen|$effectiveUserScope|';
    final result = <String, ({int messageId, int senderId})>{};

    for (final key in box.keys) {
      final keyStr = key.toString();
      if (keyStr.startsWith(prefix)) {
        final conversationId = keyStr.substring(prefix.length);
        final raw = box.get(keyStr);
        if (raw != null && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              final msgId = decoded['message_id'];
              final sId = decoded['sender_id'];
              if (msgId is int) {
                result[conversationId] = (
                  messageId: msgId,
                  senderId: sId is int ? sId : 0,
                );
              }
            }
          } catch (_) {}
        }
      }
    }
    return result;
  }

  /// Clears the pending seen ACK for a specific conversation.
  /// If [upToMessageId] is provided, only deletes if the currently stored message ID
  /// is <= [upToMessageId], protecting against overwriting a newer concurrent read.
  Future<void> clearPendingSeenAck({
    required String conversationId,
    int? upToMessageId,
    String? targetUserScope,
  }) async {
    await _coordinatePendingClear();
    await _ensureInitialized();
    final box = _box;
    if (box == null || !box.isOpen) return;

    final effectiveUserScope = targetUserScope ?? resolveCurrentUserScope();
    final key = _generatePendingSeenKey(conversationId, effectiveUserScope);

    if (upToMessageId != null) {
      final raw = box.get(key);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final storedId = decoded['message_id'];
            if (storedId is int && storedId > upToMessageId) {
              return;
            }
          }
        } catch (_) {}
      }
    }

    await box.delete(key);
  }

  /// Reads cached confirmed messages and watermarks for a conversation.
  Future<({List<ChatMessage> messages, dynamic watermarks})?> getMessages({
    required String conversationId,
    String? targetUserScope,
  }) async {
    await _coordinatePendingClear();
    await _ensureInitialized();
    final box = _box;
    if (box == null || !box.isOpen) return null;

    final effectiveUserScope = targetUserScope ?? resolveCurrentUserScope();
    final key = _generateKey(conversationId, effectiveUserScope);

    final raw = box.get(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);

      // Verify user scope match
      final storedUserScope = map['user_scope']?.toString();
      if (storedUserScope != null && storedUserScope != effectiveUserScope) {
        return null;
      }

      final rawMessages = map['messages'];
      final messages = <ChatMessage>[];
      if (rawMessages is List) {
        for (final item in rawMessages) {
          if (item is Map) {
            messages.add(
              ChatMessage.fromJson(
                Map<String, dynamic>.from(item),
                currentUserId: effectiveUserScope,
              ),
            );
          }
        }
      }
      final watermarks = map['watermarks'];
      return (messages: messages, watermarks: watermarks);
    } catch (e, st) {
      log('Error reading message cache: $e', name: 'ChatMessageCache', stackTrace: st);
      return null;
    }
  }

  /// Clears cached messages for a specific conversation.
  Future<void> clearForConversation(
    String conversationId, {
    String? targetUserScope,
  }) async {
    await _coordinatePendingClear();
    await _ensureInitialized();
    final box = _box;
    if (box == null || !box.isOpen) return;

    final effectiveUserScope = targetUserScope ?? resolveCurrentUserScope();
    final key = _generateKey(conversationId, effectiveUserScope);
    await box.delete(key);
    final pendingKey = _generatePendingSeenKey(conversationId, effectiveUserScope);
    await box.delete(pendingKey);
  }

  /// Wipes all cached message histories across all conversations.
  Future<void> clearAll() {
    _sessionEpoch++;

    final prevClear = _activeClearFuture ?? Future.value();
    late final Future<void> currentClear;
    currentClear = prevClear.then((_) => _doClearAll()).whenComplete(() {
      if (identical(_activeClearFuture, currentClear)) {
        _activeClearFuture = null;
      }
    });
    _activeClearFuture = currentClear;
    return currentClear;
  }

  Future<void> _doClearAll() async {
    try {
      final hold = clearHoldCompleter;
      if (hold != null) {
        await hold.future;
      }
      if (_box == null && !Hive.isBoxOpen('chat_message_history')) {
        return;
      }
      await _ensureInitialized();
      final box = _box;
      if (box != null && box.isOpen) {
        await box.clear();
      }
    } catch (_) {
      // Ignore if Hive box could not be opened or cleared
    }
  }
}
