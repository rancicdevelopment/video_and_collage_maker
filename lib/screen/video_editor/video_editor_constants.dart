// ── Layout ────────────────────────────────────────────────────────────────────
const double kVeRulerHeight          = 32.0;
const double kVeVideoTrackHeight     = 80.0;  // taller for filmstrip
const double kVeAudioTrackHeight     = 64.0;
const double kVeCollapsedTrackHeight = 24.0;  // minimised row
const double kVeTransitionRowHeight  = 40.0;  // dedicated transition row
const double kVeTrackGap             = 6.0;
const double kVeHandleWidth       = 20.0;
const double kVePlayheadWidth     = 2.0;
const double kVePreviewMinHeight  = 180.0;
// Reference canvas height used to normalise fontSize/overlayScale across
// all render targets (editor preview, fullscreen, FFmpeg export).
// fontSize values in the model are "pixels at kVeRefCanvasH".
const double kVeRefCanvasH = kVePreviewMinHeight;

// ── Zoom ──────────────────────────────────────────────────────────────────────
const double kVeDefaultPPS = 0.75; // pixels per second at default zoom
const double kVeMinPPS     = 0.3;
const double kVeMaxPPS     = 40.0;
const double kVeZoomStep   = 1.4;
