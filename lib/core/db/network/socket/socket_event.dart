import 'dart:convert';
import 'dart:developer';

typedef SocketEventCallback = void Function(
    Map<String, dynamic> event,
    );

List<Map<String, dynamic>> decodeSocketEvents(dynamic raw) {
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;

    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map(
            (event) => Map<String, dynamic>.from(event),
      )
          .toList();
    }

    if (decoded is Map) {
      return [
        Map<String, dynamic>.from(decoded),
      ];
    }
  } catch (e) {
    log(
      'Socket event decode failed: $e',
      name: 'SocketEvent',
    );
  }

  return [];
}