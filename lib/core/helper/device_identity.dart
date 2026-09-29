import 'dart:developer';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../../application/app_version/app_version_service.dart';

/// The `device` block the accounts service wants on every session-creating
/// call. It identifies the install, so the server can list and revoke sessions
/// per device.
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.appVersion,
  });

  final String deviceId;
  final String name;
  final String platform;
  final String appVersion;

  static DeviceIdentity? _cached;

  /// Reads the device once per run and keeps it — the platform channel call is
  /// not free, and nothing it returns changes while the app is alive.
  static Future<DeviceIdentity> resolve() async {
    final cached = _cached;
    if (cached != null) return cached;

    final plugin = DeviceInfoPlugin();
    var deviceId = '';
    var name = '';

    try {
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        // Android's `id` is per install + signing key: stable while the app
        // stays installed, gone on uninstall, which is what a session should
        // track.
        deviceId = info.id;
        name = '${info.manufacturer} ${info.model}'.trim();
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        deviceId = info.identifierForVendor ?? '';
        name = info.name.isNotEmpty ? info.name : info.utsname.machine;
      }
    } catch (error) {
      log('could not read device info: $error', name: 'DeviceIdentity');
    }

    final platform = Platform.isIOS ? 'ios' : 'android';
    return _cached = DeviceIdentity(
      // An empty id would let the server open a fresh session on every call,
      // so fall back to something stable for the run at least.
      deviceId: deviceId.isNotEmpty ? deviceId : 'dev_${platform}_unknown',
      name: name.isNotEmpty ? name : platform,
      platform: platform,
      appVersion: AppVersionService.appVersion.isNotEmpty
          ? AppVersionService.appVersion
          : '1.0.0',
    );
  }

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'name': name,
    'platform': platform,
    'app_version': appVersion,
  };
}
