import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

Future<void> requestAppPermissions() async {
  try {
    await Permission.notification.request();
    await Permission.camera.request();
    
    if (Platform.isAndroid) {
      // For Android 13+ use photos, for older use storage
      await Permission.photos.request();
      await Permission.storage.request();
    } else {
      await Permission.storage.request();
      await Permission.photos.request();
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error requesting permissions: ');
    }
  }
}
