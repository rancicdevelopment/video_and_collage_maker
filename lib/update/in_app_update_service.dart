import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

class InAppUpdateService {
  static Future<void> checkAndUpdate() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      // Uvek immediate — ignorišemo Play preporuku jer je update obavezan.
      await InAppUpdate.performImmediateUpdate();
    } catch (e) {
      debugPrint('[UPDATE] error: $e');
    }
  }
}
