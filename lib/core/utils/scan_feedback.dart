import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';

class ScanFeedback {
  ScanFeedback._();

  static const _soundChannel = MethodChannel('com.example.wms_mobile/sound');

  static Future<bool> _isEnabled(WidgetRef ref, String key) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final settings = await db.select(db.appSettings).get();
      return settings.firstWhere((e) => e.key == key, orElse: () => AppSetting(key: key, value: 'true')).value == 'true';
    } catch (_) {
      return true;
    }
  }

  /// Trigger successful scan feedback (beep + haptic vibration)
  static Future<void> triggerSuccess(WidgetRef ref) async {
    final vibrate = await _isEnabled(ref, 'vibrate_on_scan');
    final beep = await _isEnabled(ref, 'beep_on_scan');

    try {
            if (vibrate) {
        bool? hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          Vibration.vibrate(duration: 150);
        } else {
          HapticFeedback.mediumImpact();
        }
      }
      if (beep) {
        await _soundChannel.invokeMethod('playBeep', {'type': 'success'});
      }
    } catch (_) {
      if (vibrate) HapticFeedback.vibrate();
    }
  }

  /// Trigger failed scan feedback (error beep + double haptic vibration)
  static Future<void> triggerError(WidgetRef ref) async {
    final vibrate = await _isEnabled(ref, 'vibrate_on_scan');
    final beep = await _isEnabled(ref, 'beep_on_scan');

    try {
            if (vibrate) {
        bool? hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          Vibration.vibrate(pattern: [0, 150, 100, 150]);
        } else {
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 100), () {
            HapticFeedback.heavyImpact();
          });
        }
      }
      if (beep) {
        await _soundChannel.invokeMethod('playBeep', {'type': 'error'});
      }
    } catch (_) {
      if (vibrate) HapticFeedback.vibrate();
    }
  }
}
