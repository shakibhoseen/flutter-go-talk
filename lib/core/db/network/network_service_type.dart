import '../../constants/app_constant.dart';

enum NetworkServiceType {
  /// The general authenticated backend — chat, users, messages.
  chat,

  /// Accounts service (login, tokens, sessions). Its own host, own client —
  /// it shares nothing with the chat base url.
  auth,

  /// Shared platform namespace (one level above `ecommerce/`), used by
  /// app-wide endpoints such as the startup app-status check.
  platform,
}

extension NetworkServiceTypeX on NetworkServiceType {
  String get storageKey {
    switch (this) {
      case NetworkServiceType.chat:
        return kKeyChatBaseUrlOverride;

      case NetworkServiceType.auth:
        return kKeyAuthBaseUrlOverride;
      case NetworkServiceType.platform:
        return kKeyPlatformBaseUrlOverride;
    }
  }

  String get envPrefix {
    switch (this) {
      case NetworkServiceType.chat:
        return 'CHAT_BASE_URL';

      case NetworkServiceType.auth:
        return 'AUTH_BASE_URL';
      case NetworkServiceType.platform:
        return 'PLATFORM_BASE_URL';
    }
  }
}
