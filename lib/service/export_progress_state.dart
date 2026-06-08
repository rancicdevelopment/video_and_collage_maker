import 'package:flutter/foundation.dart';

/// Global state for the ongoing export operation.
///
/// Updated by [CollagePreviewScreen] during export so that
/// [ExportProgressScreen] can reactively display the current progress
/// regardless of where it sits in the navigation stack.
class ExportProgressState {
  ExportProgressState._();
  static final instance = ExportProgressState._();

  /// Current export progress in the range 0.0–1.0.
  final ValueNotifier<double> progress = ValueNotifier(0.0);

  /// Whether an export is currently running.
  final ValueNotifier<bool> isExporting = ValueNotifier(false);

  /// Mark export as started and reset progress.
  void start() {
    isExporting.value = true;
    progress.value = 0.0;
  }

  /// Update progress (0.0–1.0).
  void update(double value) {
    progress.value = value;
  }

  /// Mark export as finished (success or error) and reset progress.
  void finish() {
    isExporting.value = false;
    progress.value = 0.0;
  }
}
