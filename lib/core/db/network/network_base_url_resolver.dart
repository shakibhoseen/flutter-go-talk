import '../../config/app_flavor_config.dart';
import 'network_service_type.dart';

/// The base url a service talks to right now.
///
/// Normally that is the flavor's url from [AppFlavorConfig]; a debug build can
/// point one service somewhere else for the rest of the session (the dev field
/// on the login screen). Overrides are in-memory only — this app has no
/// key-value store yet, so nothing survives a restart.
final class NetworkBaseUrlResolver {
  NetworkBaseUrlResolver._();

  static final Map<NetworkServiceType, String> _sessionOverrides = {};

  static String resolve(NetworkServiceType service) {
    final sessionOverride = _sessionOverrides[service];
    if (sessionOverride != null && sessionOverride.isNotEmpty) {
      return sessionOverride;
    }

    // The platform namespace has no dev UI of its own. When someone points the
    // chat service at their local backend, app-wide calls have to follow them
    // there rather than keep asking staging about a build talking elsewhere.
    if (service == NetworkServiceType.platform) {
      return AppFlavorConfig.platformBaseUrlFrom(
        resolve(NetworkServiceType.chat),
      );
    }

    return AppFlavorConfig.baseUrlFor(service);
  }

  static void setDebugOverride(NetworkServiceType service, String baseUrl) {
    if (!AppFlavorConfig.canUseDebugNetworkOverrides) {
      return;
    }
    _sessionOverrides[service] = _normalizeUrl(baseUrl);
  }

  static void clearDebugOverride(NetworkServiceType service) {
    _sessionOverrides.remove(service);
  }

  static String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }
}
