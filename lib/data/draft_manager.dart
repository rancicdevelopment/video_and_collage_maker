import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../screen/video_editor/video_editor_model.dart';

class DraftProject {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<TimelineTrack> tracks;
  final String? thumbnailPath; // path to cached thumbnail image
  final double pps;            // timeline zoom (pixels per second)
  final int playheadMs;        // playhead position in milliseconds

  DraftProject({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.modifiedAt,
    required this.tracks,
    this.thumbnailPath,
    this.pps = 80.0,
    this.playheadMs = 0,
  });

  Duration get totalDuration {
    if (tracks.isEmpty) return Duration.zero;
    return tracks
        .map((t) => t.endTime)
        .reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'thumbnailPath': thumbnailPath,
    'pps': pps,
    'playheadMs': playheadMs,
  };

  factory DraftProject.fromJson(Map<String, dynamic> json) => DraftProject(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    tracks: (json['tracks'] as List<dynamic>)
        .map((t) => TimelineTrack.fromJson(t as Map<String, dynamic>))
        .toList(),
    thumbnailPath: json['thumbnailPath'] as String?,
    pps: (json['pps'] as num?)?.toDouble() ?? 80.0,
    playheadMs: (json['playheadMs'] as num?)?.toInt() ?? 0,
  );

  DraftProject copyWith({
    String? title,
    DateTime? modifiedAt,
    List<TimelineTrack>? tracks,
    String? thumbnailPath,
    double? pps,
    int? playheadMs,
  }) =>
      DraftProject(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        tracks: tracks ?? this.tracks,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        pps: pps ?? this.pps,
        playheadMs: playheadMs ?? this.playheadMs,
      );
}

class DraftManager {
  DraftManager._();
  static final DraftManager instance = DraftManager._();

  Future<Directory> _draftsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/drafts');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Save or update a draft. Returns the saved draft.
  Future<DraftProject> save(DraftProject draft) async {
    final dir = await _draftsDir();
    final file = File('${dir.path}/${draft.id}.json');

    // Copy thumbnail to the drafts folder so it survives temp dir clears.
    String? persistedThumb = draft.thumbnailPath;
    if (draft.thumbnailPath != null) {
      final src = File(draft.thumbnailPath!);
      if (src.existsSync()) {
        final dest = File('${dir.path}/thumb_${draft.id}.jpg');
        await src.copy(dest.path);
        persistedThumb = dest.path;
      }
    }

    final saved = draft.copyWith(
      modifiedAt: DateTime.now(),
      thumbnailPath: persistedThumb,
    );
    await file.writeAsString(jsonEncode(saved.toJson()));
    return saved;
  }

  /// Load all drafts sorted newest-first.
  Future<List<DraftProject>> loadAll() async {
    final dir = await _draftsDir();
    final drafts = <DraftProject>[];

    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
          final draft = DraftProject.fromJson(json);
          // Verify thumbnail still exists and is non-empty; clear if not.
          final thumbFile = draft.thumbnailPath != null ? File(draft.thumbnailPath!) : null;
          if (thumbFile != null &&
              (!thumbFile.existsSync() || thumbFile.lengthSync() == 0)) {
            drafts.add(draft.copyWith(thumbnailPath: null));
          } else {
            drafts.add(draft);
          }
        } catch (e) {
          // Corrupted draft file — skip it.
        }
      }
    }

    drafts.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return drafts;
  }

  /// Load a single draft by id. Returns null if not found.
  Future<DraftProject?> load(String id) async {
    final dir = await _draftsDir();
    final file = File('${dir.path}/$id.json');
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return DraftProject.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Delete a draft and its thumbnail.
  Future<void> delete(String id) async {
    final dir = await _draftsDir();
    final file = File('${dir.path}/$id.json');
    final thumb = File('${dir.path}/thumb_$id.jpg');
    if (file.existsSync()) file.deleteSync();
    if (thumb.existsSync()) thumb.deleteSync();
  }

  /// Create a new empty draft with a generated id.
  DraftProject create() => DraftProject(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    title: 'Project ${DateTime.now().day}/${DateTime.now().month}',
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
    tracks: [],
  );
}
