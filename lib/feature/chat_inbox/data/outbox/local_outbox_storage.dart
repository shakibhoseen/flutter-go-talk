import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'pending_outbox_message.dart';

/// Contract for persistent local outbox storage to preserve pending messages across app restarts.
abstract class LocalOutboxStorage {
  Future<void> save(PendingOutboxMessage message);
  Future<void> remove(String clientMessageId);
  Future<List<PendingOutboxMessage>> getMessagesForConversation(
    String conversationId, {
    String? targetUserScope,
  });
  Future<List<PendingOutboxMessage>> getAllMessages({String? targetUserScope});
  Future<void> clear({String? targetUserScope});
}

/// SharedPreferences-backed implementation of [LocalOutboxStorage].
class SharedPreferencesOutboxStorage implements LocalOutboxStorage {
  static const String storageKey = 'chat_outbox_pending_messages';

  final SharedPreferences? _customPrefs;

  SharedPreferencesOutboxStorage([this._customPrefs]);

  Future<SharedPreferences> _getPrefs() async {
    return _customPrefs ?? await SharedPreferences.getInstance();
  }

  static bool _matchesUserScope(PendingOutboxMessage m, String? targetUserScope) {
    if (targetUserScope == null) return true;
    if (targetUserScope.isEmpty || targetUserScope == 'guest') {
      return m.senderId.isEmpty || m.senderId == 'guest';
    }
    return m.senderId == targetUserScope;
  }

  @override
  Future<void> save(PendingOutboxMessage message) async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(storageKey);
      final map = <String, dynamic>{};
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            map.addAll(decoded);
          }
        } catch (_) {}
      }

      map[message.clientMessageId] = message.toJson();
      await prefs.setString(storageKey, jsonEncode(map));
    } catch (_) {}
  }

  @override
  Future<void> remove(String clientMessageId) async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        decoded.remove(clientMessageId);
        await prefs.setString(storageKey, jsonEncode(decoded));
      }
    } catch (_) {}
  }

  @override
  Future<List<PendingOutboxMessage>> getMessagesForConversation(
    String conversationId, {
    String? targetUserScope,
  }) async {
    final all = await getAllMessages(targetUserScope: targetUserScope);
    return all.where((m) => m.conversationId == conversationId).toList();
  }

  @override
  Future<List<PendingOutboxMessage>> getAllMessages({
    String? targetUserScope,
  }) async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final list = <PendingOutboxMessage>[];
        for (final entry in decoded.values) {
          PendingOutboxMessage? msg;
          if (entry is Map<String, dynamic>) {
            msg = PendingOutboxMessage.fromJson(entry);
          } else if (entry is Map) {
            msg = PendingOutboxMessage.fromJson(Map<String, dynamic>.from(entry));
          }
          if (msg != null && _matchesUserScope(msg, targetUserScope)) {
            list.add(msg);
          }
        }
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return list;
      }
    } catch (_) {}
    return [];
  }

  @override
  Future<void> clear({String? targetUserScope}) async {
    try {
      final prefs = await _getPrefs();
      if (targetUserScope == null) {
        await prefs.remove(storageKey);
      } else {
        final raw = prefs.getString(storageKey);
        if (raw == null || raw.isEmpty) return;
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.removeWhere((key, value) {
            if (value is Map<String, dynamic>) {
              final msg = PendingOutboxMessage.fromJson(value);
              return _matchesUserScope(msg, targetUserScope);
            }
            return false;
          });
          await prefs.setString(storageKey, jsonEncode(decoded));
        }
      }
    } catch (_) {}
  }
}

/// In-memory implementation of [LocalOutboxStorage] useful for fast testing or ephemeral sessions.
class InMemoryOutboxStorage implements LocalOutboxStorage {
  final Map<String, PendingOutboxMessage> _items = {};

  static bool _matchesUserScope(PendingOutboxMessage m, String? targetUserScope) {
    if (targetUserScope == null) return true;
    if (targetUserScope.isEmpty || targetUserScope == 'guest') {
      return m.senderId.isEmpty || m.senderId == 'guest';
    }
    return m.senderId == targetUserScope;
  }

  @override
  Future<void> save(PendingOutboxMessage message) async {
    _items[message.clientMessageId] = message;
  }

  @override
  Future<void> remove(String clientMessageId) async {
    _items.remove(clientMessageId);
  }

  @override
  Future<List<PendingOutboxMessage>> getMessagesForConversation(
    String conversationId, {
    String? targetUserScope,
  }) async {
    final list = _items.values
        .where((m) =>
            m.conversationId == conversationId &&
            _matchesUserScope(m, targetUserScope))
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<List<PendingOutboxMessage>> getAllMessages({
    String? targetUserScope,
  }) async {
    final list = _items.values
        .where((m) => _matchesUserScope(m, targetUserScope))
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<void> clear({String? targetUserScope}) async {
    if (targetUserScope == null) {
      _items.clear();
    } else {
      _items.removeWhere((k, m) => _matchesUserScope(m, targetUserScope));
    }
  }
}

