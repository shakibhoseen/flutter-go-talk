import 'package:permission_handler/permission_handler.dart';

class CallPermissionService {
  CallPermissionService._();
  static final CallPermissionService instance = CallPermissionService._();

  Future<bool> requestPermissions({required bool isVideo}) async {
    try {
      final micStatus = await Permission.microphone.request();

      if (micStatus.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }

      if (isVideo) {
        final cameraStatus = await Permission.camera.request();
        if (cameraStatus.isPermanentlyDenied) {
          await openAppSettings();
          return false;
        }
        if (!cameraStatus.isGranted) {
          return false;
        }
      }

      if (!micStatus.isGranted) {
        return false;
      }

      return true;
    } catch (_) {
      // If permission_handler native channel is not attached yet (e.g. hot reload),
      // allow WebRTC's native getUserMedia to request permissions directly.
      return true;
    }
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }
}
