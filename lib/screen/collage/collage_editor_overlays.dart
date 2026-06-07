part of 'collage_editor_screen.dart';

// ── Overlay models ────────────────────────────────────────────────────────────

class _TextOverlay {
  String text;
  double x, y;       // normalized center 0..1
  double fontSize;
  Color color;
  Color bgColor;
  bool bold;
  bool italic;
  bool shadow;
  double scale;
  double rotation;

  _TextOverlay({
    this.text = '',
    this.x = 0.5,
    this.y = 0.38,
    this.fontSize = 20,
    this.color = Colors.white,
    this.bgColor = Colors.transparent,
    this.bold = false,
    this.italic = false,
    this.shadow = false,
    this.scale = 1.0,
    this.rotation = 0,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'x': x,
        'y': y,
        'fontSize': fontSize,
        'color': color.toARGB32(),
        'bgColor': bgColor.toARGB32(),
        'bold': bold,
        'italic': italic,
        'shadow': shadow,
        'scale': scale,
        'rotation': rotation,
      };

  factory _TextOverlay.fromJson(Map<String, dynamic> j) => _TextOverlay(
        text: j['text'] as String? ?? '',
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.38,
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 20,
        color: Color((j['color'] as num?)?.toInt() ?? Colors.white.toARGB32()),
        bgColor: Color((j['bgColor'] as num?)?.toInt() ?? Colors.transparent.toARGB32()),
        bold: (j['bold'] as bool?) ?? false,
        italic: (j['italic'] as bool?) ?? false,
        shadow: (j['shadow'] as bool?) ?? false,
        scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
      );
}

class _StickerOverlay {
  String emoji;
  double x, y;       // normalized center 0..1
  double scale;
  double rotation;

  _StickerOverlay({
    required this.emoji,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.rotation = 0,
  });

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
      };

  factory _StickerOverlay.fromJson(Map<String, dynamic> j) => _StickerOverlay(
        emoji: j['emoji'] as String,
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.5,
        scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
      );
}

class _GifOverlay {
  String filePath;
  double x, y;       // normalized center 0..1
  double scale;
  double rotation;

  _GifOverlay({
    required this.filePath,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.rotation = 0,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
      };

  factory _GifOverlay.fromJson(Map<String, dynamic> j) => _GifOverlay(
        filePath: j['filePath'] as String,
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.5,
        scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
      );
}
