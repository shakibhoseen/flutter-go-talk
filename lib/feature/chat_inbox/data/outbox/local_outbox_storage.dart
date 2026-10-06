import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'pending_outbox_message.dart';

/// Contract for persistent local outbox storage to preserve pending messages across app restarts.
abstract class LocalOutboxStorage {
  Future<void> save(PendingOutboxMessage message);
  Future<void> remove(String clientMessageId);
  Future<List<PendingOutboxMessage>> getMessagesForConversation(String conversationId);
  Future<List<PendingOutboxMessage>> getAllMessages();
  Future<void> clear();
}

/// SharedPreferences-backed implementation of [LocalOutboxStorage].
class SharedPreferencesOutboxStorage implements LocalOutboxStorage {
  static const String storageKey = 'chat_outbox_pending_messages';

  final SharedPreferences? _customPrefs;

  SharedPreferencesOutboxStorage([this._customPrefs]);

  Future<SharedPreferences> _getPrefs() async {
    return _customPrefs ?? await SharedPreferences.getInstance();
  }

  @override
  Future<void> save(PendingOutboxMessage message) async {
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
  }

  @override
  Future<void> remove(String clientMessageId) async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        decoded.remove(clientMessageId);
        await prefs.setString(storageKey, jsonEncode(decoded));
      }
    } catch (_) {}
  }

  @override
  Future<List<PendingOutboxMessage>> getMessagesForConversation(
    String conversationId,
  ) async {
    final all = await getAllMessages();
    return all.where((m) => m.conversationId == conversationId).toList();
  }

  @override
  Future<List<PendingOutboxMessage>> getAllMessages() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final list = <PendingOutboxMessage>[];
        for (final entry in decoded.values) {
          if (entry is Map<String, dynamic>) {
            list.add(PendingOutboxMessage.fromJson(entry));
          } else if (entry is Map) {
            list.add(PendingOutboxMessage.fromJson(Map<String, dynamic>.from(entry)));
          }
        }
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return list;
      }
    } catch (_) {}
    return [];
  }

  @override
  Future<void> clear() async {
    final prefs = await _getPrefs();
    await prefs.remove(storageKey);
  }
}

/// In-memory implementation of [LocalOutboxStorage] useful for fast testing or ephemeral sessions.
class InMemoryOutboxStorage implements LocalOutboxStorage {
  final Map<String, PendingOutboxMessage> _items = {};

  @override
  Future<void> save(PendingOutboxMessage message) async {
    _items[message.clientMessageId] = message;
  }

  @override
  Future<void> remove(String clientMessageId) async {
    _items.remove(clientMessageId);
  }

  @override
  Future<List<PendingOutboxMessage>> getMessagesForConversation(String conversationId) async {
    final list = _items.values.where((m) => m.conversationId == conversationId).toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<List<PendingOutboxMessage>> getAllMessages() async {
    final list = _items.values.toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<void> clear() async {
    _items.clear();
  }
}

