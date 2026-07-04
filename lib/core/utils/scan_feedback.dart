import 'package:flutter/services.dart';

class ScanFeedback {
  ScanFeedback._();

  static const _soundChannel = MethodChannel('com.example.wms_mobile/sound');

  /// Trigger successful scan feedback (beep + haptic vibration)
  static Future<void> triggerSuccess() async {
    try {
      // Platform Haptic Vibration
      HapticFeedback.mediumImpact();
      
      // Native Sound Beep
      await _soundChannel.invokeMethod('playBeep', {'type': 'success'});
    } catch (_) {
      // Fallback to standard vibration if method channel fails
      HapticFeedback.vibrate();
    }
  }

  /// Trigger failed scan feedback (error beep + double haptic vibration)
  static Future<void> triggerError() async {
    try {
      // Platform Haptic Vibration
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 100), () {
        HapticFeedback.heavyImpact();
      });

      // Native Sound Beep
      await _soundChannel.invokeMethod('playBeep', {'type': 'error'});
    } catch (_) {
      // Fallback
      HapticFeedback.vibrate();
    }
  }
}
