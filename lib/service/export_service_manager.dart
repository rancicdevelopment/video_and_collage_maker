import 'dart:io';

import 'package:flutter/services.dart';

import '../ad/app_open_ad_manager.dart';

/// Wraps the Android foreground-service MethodChannel.
///
/// Call [start] before beginning an FFmpeg export, [updateProgress] from the
/// statistics callback (throttled to ~3% increments), and [stop] when the
/// export finishes or fails.
///
/// All methods are no-ops on non-Android platforms.
class ExportServiceManager {
  ExportServiceManager._();

  static const _channel =
      MethodChannel('com.video.rd.editor/export_service');

  // Last progress value sent to Android — used to throttle IPC calls.
  static int _lastSentProgress = -1;

  /// Requests notification permission (Android 13+) then starts the
  /// foreground service so the export survives app-backgrounding.
  ///
  /// The app-open ad is suppressed for the next resume because the
  /// system permission dialog briefly backgrounds the app on Android 13+.
  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      // Suppress the App Open ad that fires when the permission dialog
      // closes and the app comes back to the foreground.
      AppOpenAdManager.instance.suppressNextResume();
      await _channel.invokeMethod<void>('requestNotificationPermission');
      await _channel.invokeMethod<void>('startExportService');
      _lastSentProgress = -1;
    } catch (e) {
      // Non-fatal — export still works without the foreground service.
    }
  }

  /// Updates the notification progress bar.
  ///
  /// [progress] must be in the range 0.0–1.0.
  /// Updates are throttled: the IPC call is skipped when the change is
  /// less than 3 percentage points to avoid hammering the binder.
  static Future<void> updateProgress(double progress) async {
    if (!Platform.isAndroid) return;
    final pct = (progress * 100).round().clamp(0, 100);
    if ((pct - _lastSentProgress).abs() < 3 && pct != 100) return;
    _lastSentProgress = pct;
    try {
      await _channel.invokeMethod<void>(
        'updateExportProgress',
        {'progress': progress},
      );
    } catch (_) {
      // Ignore — the export itself is unaffected.
    }
  }

  /// Stops the foreground service and removes the notification.
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    _lastSentProgress = -1;
    try {
      await _channel.invokeMethod<void>('stopExportService');
    } catch (_) {}
  }
}
