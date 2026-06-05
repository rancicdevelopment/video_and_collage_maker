import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ── Data types ────────────────────────────────────────────────────────────────

class SrtEntry {
  final int index;
  final Duration start;
  final Duration end;
  final String text;

  const SrtEntry({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });

  String toSrtBlock() {
    return '$index\n${_fmt(start)} --> ${_fmt(end)}\n$text';
  }

  static String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }
}

typedef ProgressCallback = void Function(String status, double progress);

// ── Service ───────────────────────────────────────────────────────────────────

class CaptionsService {
  static const _chunkSecs = 55;
  static const _wordsPerEntry = 8;
  static const _apiBase = 'https://speech.googleapis.com/v1/speech:recognize';

  /// Main entry point. Returns path to the generated .srt file.
  Future<String> transcribeVideo({
    required String videoPath,
    required String apiKey,
    required String languageCode,
    ProgressCallback? onProgress,
  }) async {
    onProgress?.call('Extracting audio…', 0.05);
    final audioPath = await _extractAudio(videoPath);

    onProgress?.call('Analysing duration…', 0.12);
    final totalSecs = await _getDuration(audioPath);

    final chunks = await _splitAudio(audioPath, totalSecs);
    final allWords = <_Word>[];

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final frac = 0.15 + 0.75 * (i / chunks.length);
      onProgress?.call('Transcribing ${i + 1}/${chunks.length}…', frac);

      final words = await _transcribeChunk(
        chunk.path,
        apiKey,
        languageCode,
        chunk.offset,
      );
      allWords.addAll(words);

      if (chunk.path != audioPath) {
        await File(chunk.path).delete().catchError((_) => File(chunk.path));
      }
    }

    await File(audioPath).delete().catchError((_) => File(audioPath));

    onProgress?.call('Generating SRT…', 0.93);
    final entries = _buildEntries(allWords);
    final srtContent = entries.map((e) => e.toSrtBlock()).join('\n\n');

    final dir = await getTemporaryDirectory();
    final srtPath =
        '${dir.path}/captions_${DateTime.now().millisecondsSinceEpoch}.srt';
    await File(srtPath).writeAsString(srtContent, encoding: utf8);

    onProgress?.call('Done', 1.0);
    return srtPath;
  }

  /// Burns .srt subtitles into the video. Returns path to the new video file.
  Future<String> burnSubtitles({
    required String videoPath,
    required String srtPath,
    ProgressCallback? onProgress,
  }) async {
    onProgress?.call('Burning subtitles…', 0.1);
    final dir = await getTemporaryDirectory();
    final output =
        '${dir.path}/captioned_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Escape colons and backslashes for the subtitles filter path argument.
    final escapedSrt =
        srtPath.replaceAll('\\', '/').replaceAll(':', '\\:');

    const style =
        "FontSize=18,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,"
        "Outline=2,Shadow=1,Alignment=2,MarginV=24";

    final session = await FFmpegKit.execute(
      '-y -i "$videoPath" '
      '-vf "subtitles=$escapedSrt:force_style=\'$style\'" '
      '-c:v libx264 -preset fast -crf 22 -c:a copy '
      '"$output"',
    );
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg burn-in failed:\n$logs');
    }
    onProgress?.call('Done', 1.0);
    return output;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Future<String> _extractAudio(String videoPath) async {
    final dir = await getTemporaryDirectory();
    final out =
        '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.flac';
    final session = await FFmpegKit.execute(
      '-y -i "$videoPath" -vn -ar 16000 -ac 1 -f flac "$out"',
    );
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      throw Exception('Audio extraction failed');
    }
    return out;
  }

  Future<double> _getDuration(String path) async {
    final session = await FFmpegKit.execute('-i "$path" -f null -');
    final logs = await session.getAllLogsAsString() ?? '';
    final m = RegExp(r'Duration:\s+(\d+):(\d+):([\d.]+)').firstMatch(logs);
    if (m == null) return 0;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final s = double.parse(m.group(3)!);
    return h * 3600 + min * 60 + s;
  }

  Future<List<_AudioChunk>> _splitAudio(
      String audioPath, double totalSecs) async {
    if (totalSecs <= _chunkSecs || totalSecs == 0) {
      return [_AudioChunk(path: audioPath, offset: Duration.zero)];
    }

    final dir = await getTemporaryDirectory();
    final chunks = <_AudioChunk>[];
    double offset = 0;
    int i = 0;

    while (offset < totalSecs) {
      final chunkPath =
          '${dir.path}/chunk_${i}_${DateTime.now().millisecondsSinceEpoch}.flac';
      final session = await FFmpegKit.execute(
        '-y -i "$audioPath" -ss $offset -t $_chunkSecs "$chunkPath"',
      );
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && File(chunkPath).existsSync()) {
        chunks.add(_AudioChunk(
          path: chunkPath,
          offset: Duration(milliseconds: (offset * 1000).round()),
        ));
      }
      offset += _chunkSecs;
      i++;
    }
    return chunks;
  }

  Future<List<_Word>> _transcribeChunk(
    String audioPath,
    String apiKey,
    String languageCode,
    Duration offset,
  ) async {
    final audioBytes = await File(audioPath).readAsBytes();
    final base64Audio = base64Encode(audioBytes);

    final body = jsonEncode({
      'config': {
        'encoding': 'FLAC',
        'sampleRateHertz': 16000,
        'languageCode': languageCode,
        'enableWordTimeOffsets': true,
        'enableAutomaticPunctuation': true,
        'model': 'video',
      },
      'audio': {'content': base64Audio},
    });

    final response = await http.post(
      Uri.parse('$_apiBase?key=$apiKey'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: body,
    );

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      final msg = (err['error'] as Map?)?['message'] ?? response.body;
      throw Exception(msg);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? [];
    final words = <_Word>[];

    for (final result in results) {
      final alts = result['alternatives'] as List<dynamic>? ?? [];
      if (alts.isEmpty) continue;
      final wordList = alts[0]['words'] as List<dynamic>? ?? [];
      for (final w in wordList) {
        final startMs =
            (_parseSeconds(w['startTime'] as String? ?? '0s') * 1000).round();
        final endMs =
            (_parseSeconds(w['endTime'] as String? ?? '0s') * 1000).round();
        words.add(_Word(
          text: w['word'] as String,
          start: offset + Duration(milliseconds: startMs),
          end: offset + Duration(milliseconds: endMs),
        ));
      }
    }
    return words;
  }

  double _parseSeconds(String s) =>
      double.tryParse(s.replaceAll('s', '')) ?? 0;

  List<SrtEntry> _buildEntries(List<_Word> words) {
    final entries = <SrtEntry>[];
    int idx = 1;
    int i = 0;
    while (i < words.length) {
      final group = words.skip(i).take(_wordsPerEntry).toList();
      entries.add(SrtEntry(
        index: idx++,
        start: group.first.start,
        end: group.last.end,
        text: group.map((w) => w.text).join(' '),
      ));
      i += _wordsPerEntry;
    }
    return entries;
  }
}

// ── Internal models ───────────────────────────────────────────────────────────

class _Word {
  final String text;
  final Duration start;
  final Duration end;
  const _Word({required this.text, required this.start, required this.end});
}

class _AudioChunk {
  final String path;
  final Duration offset;
  const _AudioChunk({required this.path, required this.offset});
}
