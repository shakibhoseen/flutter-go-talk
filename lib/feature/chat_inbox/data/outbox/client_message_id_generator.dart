import 'package:uuid/uuid.dart';

/// Helper to generate UUID v4 identifiers for outgoing chat messages.
/// 
/// A single logical message must have its clientMessageId generated once
/// and reused across all retries.
class ClientMessageIdGenerator {
  static const _uuid = Uuid();

  /// Generates a new random UUID v4 string.
  static String generate() => _uuid.v4();
}
