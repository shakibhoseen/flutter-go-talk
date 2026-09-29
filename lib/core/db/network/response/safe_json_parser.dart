
import 'dart:developer';

class SafeJsonParser {
  static T parse<T>(Map<String, dynamic> json, String key) {
    try {
      final value = json[key];
      if (value == null) {
        throw JsonParsingException(key, value, 'Value is null or missing.');
      }
      if (value is! T) {
        throw FormatException('Expected type $T for key "$key", but got ${value.runtimeType}');
      }
      return value;
    } catch (e) {
      if (e is JsonParsingException || e is FormatException) {
        rethrow;
      }
      throw JsonParsingException(key, json[key], 'Unexpected error: ${e.toString()}');
    }
  }

  static T? nullableParse<T>(Map<String, dynamic> json, String key) {
    try {
      final value = json[key];
      if(value == null){
        return null;
      }
      if (value is! T) {
        throw FormatException('Expected type $T for key "$key", but got ${value.runtimeType}');
      }
      return value;
    } catch (e) {
      if (e is JsonParsingException || e is FormatException) {
        rethrow;
      }
      throw JsonParsingException(key, json[key], 'Unexpected error: ${e.toString()}');
    }
  }
}



class JsonParsingException implements Exception {
  final String key;
  final dynamic value;
  final String message;

  JsonParsingException(this.key, this.value, this.message) {
    // Log the error when the exception is created
    log('JsonParsingException: Error parsing key "$key" with value "$value". $message');
  }

  @override
  String toString() {
    return 'JsonParsingException: Error parsing key "$key" with value "$value". $message';
  }
}