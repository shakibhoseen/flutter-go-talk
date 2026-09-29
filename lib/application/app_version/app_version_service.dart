import 'dart:developer';

import 'package:package_info_plus/package_info_plus.dart';

/// The running build's version, read once at startup so request headers and
/// any version gate can stay synchronous.
final class AppVersionService {
  AppVersionService._();

  static String _appVersion = '';
  static String _buildNumber = '';

  static String get appVersion => _appVersion;

  static String get buildNumber => _buildNumber;

  /// Safe to call more than once; a failure here must never block startup, so
  /// the fields simply stay empty and the headers go out without them.
  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
      _buildNumber = info.buildNumber;
    } catch (error) {
      log('could not read package info: $error', name: 'AppVersionService');
    }
  }
}
