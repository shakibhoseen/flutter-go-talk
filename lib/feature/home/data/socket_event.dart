import 'dart:convert';

/// Decodes a raw [ChatSocketService] message into `{type, payload}` JSON.
/// Shared by [ChatViewModel] (conversation list) and `ChatThreadPage` (an
/// open thread) — both need the same defensive parsing without duplicating
/// it, since either can receive a malformed frame independently.
Map<String, dynamic>? decodeSocketEvent(dynamic raw) {
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    // Not JSON, or not a map — ignore rather than crash the socket listener.
  }
  return null;
}
