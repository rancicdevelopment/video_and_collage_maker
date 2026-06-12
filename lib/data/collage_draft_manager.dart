import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

// ── Per-cell serializable state ───────────────────────────────────────────────

class CollageCellState {
  final String? filePath;
  final bool isVideo;
  final int durationMs;
  final int trimStartMs;
  final int trimEndMs;
  final double volume;
  final int rotSteps;
  final bool flipH;
  final bool flipV;
  final double scale;
  final double angle;
  final double offsetX;
  final double offsetY;
  final int filterIdx;
  final double brightness;
  final double contrast;
  final double saturation;
  final double hue;
  final double temperature;
  final double speed;
  final bool repeating;

  const CollageCellState({
    this.filePath,
    this.isVideo = true,
    this.durationMs = 0,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.volume = 1.0,
    this.rotSteps = 0,
    this.flipH = false,
    this.flipV = false,
    this.scale = 1.0,
    this.angle = 0.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.filterIdx = 0,
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.hue = 0.0,
    this.temperature = 0.0,
    this.speed = 1.0,
    this.repeating = true,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'isVideo': isVideo,
        'durationMs': durationMs,
        'trimStartMs': trimStartMs,
        'trimEndMs': trimEndMs,
        'volume': volume,
        'rotSteps': rotSteps,
        'flipH': flipH,
        'flipV': flipV,
        'scale': scale,
        'angle': angle,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'filterIdx': filterIdx,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'hue': hue,
        'temperature': temperature,
        'speed': speed,
        'repeating': repeating,
      };

  factory CollageCellState.fromJson(Map<String, dynamic> j) => CollageCellState(
        filePath: j['filePath'] as String?,
        isVideo: (j['isVideo'] as bool?) ?? true,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        trimStartMs: (j['trimStartMs'] as num?)?.toInt() ?? 0,
        trimEndMs: (j['trimEndMs'] as num?)?.toInt() ?? 0,
        volume: (j['volume'] as num?)?.toDouble() ?? 1.0,
        rotSteps: (j['rotSteps'] as num?)?.toInt() ?? 0,
        flipH: (j['flipH'] as bool?) ?? false,
        flipV: (j['flipV'] as bool?) ?? false,
        scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
        angle: (j['angle'] as num?)?.toDouble() ?? 0.0,
        offsetX: (j['offsetX'] as num?)?.toDouble() ?? 0.0,
        offsetY: (j['offsetY'] as num?)?.toDouble() ?? 0.0,
        filterIdx: (j['filterIdx'] as num?)?.toInt() ?? 0,
        brightness: (j['brightness'] as num?)?.toDouble() ?? 0.0,
        contrast: (j['contrast'] as num?)?.toDouble() ?? 1.0,
        saturation: (j['saturation'] as num?)?.toDouble() ?? 1.0,
        hue: (j['hue'] as num?)?.toDouble() ?? 0.0,
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.0,
        speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
        repeating: (j['repeating'] as bool?) ?? true,
      );
}

// ── Collage draft ─────────────────────────────────────────────────────────────

class CollageDraft {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String layoutId;
  final List<CollageCellState> cells;

  /// Positions of dividers in the same order as _computeDividers produces them.
  final List<double> dividerPositions;

  final int bgColorValue; // Color.value (ARGB)
  final double borderGap;
  final String aspectRatio; // _CollageAspect.name
  final String playMode;    // _PlayMode.name

  final String? audioPath;
  final int audioTrimStartMs;
  final int audioTrimEndMs;
  final double audioVolume;

  final String? thumbnailPath;

  /// Serialized overlay lists (each entry is the result of overlay.toJson()).
  final List<Map<String, dynamic>> textOverlays;
  final List<Map<String, dynamic>> stickerOverlays;
  final List<Map<String, dynamic>> gifOverlays;

  const CollageDraft({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.modifiedAt,
    required this.layoutId,
    required this.cells,
    required this.dividerPositions,
    required this.bgColorValue,
    required this.borderGap,
    required this.aspectRatio,
    required this.playMode,
    this.audioPath,
    this.audioTrimStartMs = 0,
    this.audioTrimEndMs = 0,
    this.audioVolume = 1.0,
    this.thumbnailPath,
    this.textOverlays = const [],
    this.stickerOverlays = const [],
    this.gifOverlays = const [],
  });

  /// True if at least one cell has a media file that still exists on disk.
  bool get hasMedia => cells.any((c) =>
      c.filePath != null &&
      (c.filePath!.startsWith('content://') || File(c.filePath!).existsSync()));

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'layoutId': layoutId,
        'cells': cells.map((c) => c.toJson()).toList(),
        'dividerPositions': dividerPositions,
        'bgColorValue': bgColorValue,
        'borderGap': borderGap,
        'aspectRatio': aspectRatio,
        'playMode': playMode,
        'audioPath': audioPath,
        'audioTrimStartMs': audioTrimStartMs,
        'audioTrimEndMs': audioTrimEndMs,
        'audioVolume': audioVolume,
        'thumbnailPath': thumbnailPath,
        'textOverlays': textOverlays,
        'stickerOverlays': stickerOverlays,
        'gifOverlays': gifOverlays,
      };

  factory CollageDraft.fromJson(Map<String, dynamic> j) => CollageDraft(
        id: j['id'] as String,
        title: j['title'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        modifiedAt: DateTime.parse(j['modifiedAt'] as String),
        layoutId: j['layoutId'] as String,
        cells: (j['cells'] as List<dynamic>)
            .map((c) => CollageCellState.fromJson(c as Map<String, dynamic>))
            .toList(),
        dividerPositions: (j['dividerPositions'] as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList(),
        bgColorValue: (j['bgColorValue'] as num).toInt(),
        borderGap: (j['borderGap'] as num).toDouble(),
        aspectRatio: j['aspectRatio'] as String? ?? 'portrait916',
        playMode: j['playMode'] as String? ?? 'sync',
        audioPath: j['audioPath'] as String?,
        audioTrimStartMs: (j['audioTrimStartMs'] as num?)?.toInt() ?? 0,
        audioTrimEndMs: (j['audioTrimEndMs'] as num?)?.toInt() ?? 0,
        audioVolume: (j['audioVolume'] as num?)?.toDouble() ?? 1.0,
        thumbnailPath: j['thumbnailPath'] as String?,
        textOverlays: (j['textOverlays'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
        stickerOverlays: (j['stickerOverlays'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
        gifOverlays: (j['gifOverlays'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
      );

  CollageDraft copyWith({
    String? title,
    DateTime? modifiedAt,
    List<CollageCellState>? cells,
    List<double>? dividerPositions,
    int? bgColorValue,
    double? borderGap,
    String? aspectRatio,
    String? playMode,
    String? audioPath,
    int? audioTrimStartMs,
    int? audioTrimEndMs,
    double? audioVolume,
    String? thumbnailPath,
    List<Map<String, dynamic>>? textOverlays,
    List<Map<String, dynamic>>? stickerOverlays,
    List<Map<String, dynamic>>? gifOverlays,
  }) =>
      CollageDraft(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        layoutId: layoutId,
        cells: cells ?? this.cells,
        dividerPositions: dividerPositions ?? this.dividerPositions,
        bgColorValue: bgColorValue ?? this.bgColorValue,
        borderGap: borderGap ?? this.borderGap,
        aspectRatio: aspectRatio ?? this.aspectRatio,
        playMode: playMode ?? this.playMode,
        audioPath: audioPath ?? this.audioPath,
        audioTrimStartMs: audioTrimStartMs ?? this.audioTrimStartMs,
        audioTrimEndMs: audioTrimEndMs ?? this.audioTrimEndMs,
        audioVolume: audioVolume ?? this.audioVolume,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        textOverlays: textOverlays ?? this.textOverlays,
        stickerOverlays: stickerOverlays ?? this.stickerOverlays,
        gifOverlays: gifOverlays ?? this.gifOverlays,
      );
}

// ── Manager ───────────────────────────────────────────────────────────────────

class CollageDraftManager {
  CollageDraftManager._();
  static final CollageDraftManager instance = CollageDraftManager._();

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/collage_drafts');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<CollageDraft> save(CollageDraft draft) async {
    final dir = await _dir();

    // Persist thumbnail next to the draft JSON.
    String? persistedThumb = draft.thumbnailPath;
    if (draft.thumbnailPath != null) {
      final src = File(draft.thumbnailPath!);
      if (src.existsSync()) {
        final dest = File('${dir.path}/thumb_${draft.id}.jpg');
        if (src.path != dest.path) await src.copy(dest.path);
        persistedThumb = dest.path;
      }
    }

    final saved = draft.copyWith(
      modifiedAt: DateTime.now(),
      thumbnailPath: persistedThumb,
    );
    final file = File('${dir.path}/${draft.id}.json');
    await file.writeAsString(jsonEncode(saved.toJson()));
    return saved;
  }

  Future<List<CollageDraft>> loadAll() async {
    final dir = await _dir();
    final drafts = <CollageDraft>[];

    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final json =
              jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
          final draft = CollageDraft.fromJson(json);
          final thumbFile =
              draft.thumbnailPath != null ? File(draft.thumbnailPath!) : null;
          if (thumbFile != null &&
              (!thumbFile.existsSync() || thumbFile.lengthSync() == 0)) {
            drafts.add(draft.copyWith(thumbnailPath: null));
          } else {
            drafts.add(draft);
          }
        } catch (_) {
          // Corrupted — skip.
        }
      }
    }

    drafts.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return drafts;
  }

  /// Load a single draft by id. Returns null if not found or corrupted.
  Future<CollageDraft?> load(String id) async {
    final dir = await _dir();
    final file = File('${dir.path}/$id.json');
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return CollageDraft.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String id) async {
    final dir = await _dir();
    final file = File('${dir.path}/$id.json');
    final thumb = File('${dir.path}/thumb_$id.jpg');
    if (file.existsSync()) file.deleteSync();
    if (thumb.existsSync()) thumb.deleteSync();
  }

  CollageDraft create(String layoutId) => CollageDraft(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: 'Collage ${DateTime.now().day}/${DateTime.now().month}',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        layoutId: layoutId,
        cells: const [],
        dividerPositions: const [],
        bgColorValue: 0xFF000000,
        borderGap: 2.0,
        aspectRatio: 'portrait916',
        playMode: 'sync',
      );
}
