import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../db/network/network_service_type.dart';

/// Where each backend lives for the flavor the app was built with.
///
/// Values come from `.env` (loaded in `main`) so a host can be changed without
/// a rebuild; the constants below are only the fallback for a missing or empty
/// key, so a fresh clone still runs.
final class AppFlavorConfig {
  AppFlavorConfig._();

  static const String prod = 'prod';
  static const String qa = 'qa';

  static const String _chatProdBaseUrl =
      'http://192.168.22.156:8080/';
  static const String _chatQaBaseUrl =
      'http://192.168.22.156:8080/';

  /// The accounts service has no published production host yet, so both
  /// flavors fall back to dev until one exists. Set `AUTH_BASE_URL_PROD` in
  /// `.env` the day it does — no code change needed.
  static const String _authBaseUrl = 'http://192.168.22.156:8080/';



  static String? _debugOverride;

  static String get current => _debugOverride ?? appFlavor ?? prod;

  static bool get isQa => current == qa;

  static bool get canUseDebugNetworkOverrides => !kReleaseMode;

  static String baseUrlFor(NetworkServiceType service) =>
      baseUrlForFlavor(service, flavor: current);

  static String baseUrlForFlavor(
    NetworkServiceType service, {
    required String flavor,
  }) {
    return _readEnvValue('${service.envPrefix}_${_flavorSuffix(flavor)}') ??
        _readEnvValue(service.envPrefix) ??
        _defaultBaseUrlFor(service, flavor: flavor);
  }

  /// Debug-only flavor switch, for the dev tools on the login screen.
  static void debugOverride(String? flavor) {
    if (!canUseDebugNetworkOverrides) return;
    _debugOverride = flavor;
  }

  static String _flavorSuffix(String flavor) => flavor == qa ? 'QA' : 'PROD';

  static String _defaultBaseUrlFor(
    NetworkServiceType service, {
    required String flavor,
  }) {
    switch (service) {
      case NetworkServiceType.chat:
        return flavor == qa ? _chatQaBaseUrl : _chatProdBaseUrl;
      case NetworkServiceType.auth:
        return _authBaseUrl;

      case NetworkServiceType.platform:
        return platformBaseUrlFrom(
          baseUrlForFlavor(NetworkServiceType.chat, flavor: flavor),
        );
    }
  }

  /// The platform namespace is the chat base url without its trailing
  /// `ecommerce/` segment, so the two hosts can never drift apart.
  static String platformBaseUrlFrom(String chatBaseUrl) {
    final stripped = chatBaseUrl.replaceFirst(RegExp(r'ecommerce/?$'), '');
    return _normalizeUrl(stripped.isEmpty ? chatBaseUrl : stripped);
  }

  static String? _readEnvValue(String key) {
    // dotenv throws if it is read before `load`, and tests never load it.
    final value = dotenv.isInitialized ? dotenv.env[key] : null;
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return _normalizeUrl(value);
  }

  static String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }
}
