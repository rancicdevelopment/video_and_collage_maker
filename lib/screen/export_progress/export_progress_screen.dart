import 'package:flutter/material.dart';

import '../../service/export_progress_state.dart';

/// Full-screen view of the ongoing export progress.
///
/// Opened when the user taps the export foreground-service notification.
/// Automatically pops itself when the export finishes (success or error).
class ExportProgressScreen extends StatefulWidget {
  const ExportProgressScreen({super.key});

  @override
  State<ExportProgressScreen> createState() => _ExportProgressScreenState();
}

class _ExportProgressScreenState extends State<ExportProgressScreen> {
  @override
  void initState() {
    super.initState();
    ExportProgressState.instance.isExporting
        .addListener(_onExportStateChange);
  }

  @override
  void dispose() {
    ExportProgressState.instance.isExporting
        .removeListener(_onExportStateChange);
    super.dispose();
  }

  void _onExportStateChange() {
    if (!ExportProgressState.instance.isExporting.value && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1623),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111E2F),
        title: const Text('Export'),
        leading: const BackButton(),
      ),
      body: Center(
        child: ValueListenableBuilder<double>(
          valueListenable: ExportProgressState.instance.progress,
          builder: (context, progress, _) {
            final pct = (progress * 100).toInt();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: progress < 0.05 ? null : progress,
                          strokeWidth: 8,
                          backgroundColor: const Color(0xFF333333),
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFFE53935),
                          ),
                        ),
                      ),
                      Text(
                        progress < 0.05 ? '…' : '$pct%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Exporting video…',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
