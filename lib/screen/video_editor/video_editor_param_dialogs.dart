import 'package:flutter/material.dart';

import 'video_editor_model.dart';

// ── Volume ────────────────────────────────────────────────────────────────────

/// Shows a dialog to adjust track volume.
/// [onSetVolume] is called on every slider change (live preview on controller).
/// [onApply] is called with the chosen volume when the user confirms.
void showVeVolumeDialog({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(double v) onSetVolume,
  required void Function(double v) onApply,
}) {
  final isVideo = track.isVideo;
  final maxVol = isVideo ? 1.0 : 2.0;
  final divisions = isVideo ? 20 : 40;
  double vol = track.volume;

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: const Color(0xFF1A2535),
        title: const Text('Volume', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${(vol * 100).round()}%',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 32,
                fontWeight: FontWeight.bold),
          ),
          Slider(
            value: vol,
            min: 0.0,
            max: maxVol,
            divisions: divisions,
            activeColor: const Color(0xFF00C8FF),
            onChanged: (v) {
              setS(() => vol = v);
              onSetVolume(v);
            },
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              onSetVolume(track.volume); // revert controller to original
              Navigator.pop(ctx);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              onApply(vol);
              Navigator.pop(ctx);
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFF00C8FF))),
          ),
        ],
      ),
    ),
  );
}

// ── Speed ─────────────────────────────────────────────────────────────────────

/// Shows a speed picker dialog.
/// [onSetSpeed] is called on selection for live preview.
/// [onApply] is called with the chosen speed when the user confirms.
void showVeSpeedDialog({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(double v) onSetSpeed,
  required void Function(double v) onApply,
}) {
  double spd = track.speed;
  const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0];

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: const Color(0xFF1A2535),
        title: const Text('Speed', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: speeds.map((s) {
            final selected = (spd - s).abs() < 0.01;
            return ListTile(
              title: Text(
                '${s}x',
                style: TextStyle(
                    color: selected ? const Color(0xFF00C8FF) : Colors.white),
              ),
              trailing: selected
                  ? const Icon(Icons.check, color: Color(0xFF00C8FF))
                  : null,
              onTap: () {
                setS(() => spd = s);
                onSetSpeed(s);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              onSetSpeed(track.speed); // revert
              Navigator.pop(ctx);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              onApply(spd);
              Navigator.pop(ctx);
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFF00C8FF))),
          ),
        ],
      ),
    ),
  );
}

// ── Fade ──────────────────────────────────────────────────────────────────────

/// Shows a fade-in or fade-out duration dialog.
/// [onLiveUpdate] is called on each slider change so the preview updates.
/// [onConfirm] is called when the user presses OK (caller should push undo).
/// [onCancel] is called when the user cancels (caller should restore the track).
void showVeFadeDialog({
  required BuildContext context,
  required TimelineTrack track,
  required bool isFadeIn,
  required void Function(double secs) onLiveUpdate,
  required void Function() onConfirm,
  required void Function() onCancel,
}) {
  double secs = isFadeIn ? track.fadeInSecs : track.fadeOutSecs;

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: const Color(0xFF1A2535),
        title: Text(isFadeIn ? 'Fade In' : 'Fade Out',
            style: const TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${secs.toStringAsFixed(1)}s',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 32,
                fontWeight: FontWeight.bold),
          ),
          Slider(
            value: secs,
            min: 0.0,
            max: 30.0,
            divisions: 60,
            activeColor: const Color(0xFF00C8FF),
            onChanged: (v) {
              setS(() => secs = v);
              onLiveUpdate(v);
            },
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              onCancel();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx);
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFF00C8FF))),
          ),
        ],
      ),
    ),
  );
}

// ── Opacity ───────────────────────────────────────────────────────────────────

/// Shows an opacity dialog for video/image overlay tracks.
/// [onLiveUpdate] is called on slider changes for live preview.
/// [onConfirm] is called on OK (caller pushes undo; track is already updated).
/// [onCancel] is called on Cancel (caller restores original opacity).
void showVeOpacityDialog({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(double opacity) onLiveUpdate,
  required void Function() onConfirm,
  required void Function() onCancel,
}) {
  double opacity = track.opacity;

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: const Color(0xFF1A2535),
        title: const Text('Opacity', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${(opacity * 100).round()}%',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 32,
                fontWeight: FontWeight.bold),
          ),
          Slider(
            value: opacity,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            activeColor: const Color(0xFF00C8FF),
            onChanged: (v) {
              setS(() => opacity = v);
              onLiveUpdate(v);
            },
          ),
          const Text(
            'Controls how transparent this video clip appears\nwhen overlapping with other clips.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              onCancel();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx);
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFF00C8FF))),
          ),
        ],
      ),
    ),
  );
}

// ── Overlay Scale ─────────────────────────────────────────────────────────────

/// Shows an overlay scale dialog for video/image tracks.
/// [onApply] is called with the chosen scale when the user confirms.
void showVeScaleDialog({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(double scale) onApply,
}) {
  double scale = track.overlayScale;

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: const Color(0xFF1A2535),
        title: const Text('Overlay Scale',
            style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${(scale * 100).round()}%',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 32,
                fontWeight: FontWeight.bold),
          ),
          Slider(
            value: scale,
            min: 0.1,
            max: 1.0,
            divisions: 18,
            activeColor: const Color(0xFF00C8FF),
            onChanged: (v) => setS(() => scale = v),
          ),
          const Text(
            'Resize this clip as an overlay.\n100% = full canvas. Drag the clip in the preview to reposition it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              onApply(scale);
              Navigator.pop(ctx);
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFF00C8FF))),
          ),
        ],
      ),
    ),
  );
}

// ── Text Resize Sheet ─────────────────────────────────────────────────────────

/// Shows a bottom sheet to quickly adjust text font size.
/// [onChanged] is called live as the slider moves.
void showVeTextResizeSheet({
  required BuildContext context,
  required TimelineTrack track,
  required void Function(double fontSize) onChanged,
  double? maxHeight,
}) {
  double fontSize = track.fontSize;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A1A2E),
    constraints: maxHeight != null ? BoxConstraints(maxHeight: maxHeight) : null,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Text Size',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                Text('${fontSize.round()}',
                    style: const TextStyle(
                        color: Color(0xFFE53935),
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(ctx).copyWith(
                activeTrackColor: const Color(0xFFE53935),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFE53935),
                overlayColor: const Color(0x22E53935),
              ),
              child: Slider(
                value: fontSize,
                min: 10,
                max: 120,
                onChanged: (v) {
                  setSheet(() => fontSize = v);
                  onChanged(v);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
