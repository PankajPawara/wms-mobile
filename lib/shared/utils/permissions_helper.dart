import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

Future<void> requestAppPermissions() async {
  try {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.storage,
      Permission.photos,
      Permission.notification,
    ].request();

    if (kDebugMode) {
      print('Camera permission: ${statuses[Permission.camera]}');
      print('Storage permission: ${statuses[Permission.storage]}');
      print('Photos permission: ${statuses[Permission.photos]}');
      print('Notification permission: ${statuses[Permission.notification]}');
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error requesting permissions: $e');
    }
  }
}
