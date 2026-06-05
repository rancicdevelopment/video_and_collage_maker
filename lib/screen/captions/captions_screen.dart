import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../service/captions_service.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kBg = Color(0xFF1A1A1A);
const _kCard = Color(0xFF2A2A2A);
const _kAccent = Color(0xFFF5A623);

const _kLanguages = [
  ('English (US)', 'en-US'),
  ('English (GB)', 'en-GB'),
  ('Serbian', 'sr-RS'),
  ('German', 'de-DE'),
  ('French', 'fr-FR'),
  ('Spanish', 'es-ES'),
  ('Italian', 'it-IT'),
  ('Portuguese', 'pt-BR'),
  ('Russian', 'ru-RU'),
  ('Japanese', 'ja-JP'),
  ('Chinese (Simplified)', 'zh-CN'),
  ('Arabic', 'ar-SA'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class CaptionsScreen extends StatefulWidget {
  const CaptionsScreen({super.key});

  @override
  State<CaptionsScreen> createState() => _CaptionsScreenState();
}

class _CaptionsScreenState extends State<CaptionsScreen> {
  final _service = CaptionsService();
  final _apiKeyCtrl = TextEditingController();
  final _apiKeyFile = ValueNotifier<String>('');

  String? _videoPath;
  String? _srtPath;
  List<SrtEntry> _entries = [];

  bool _obscureKey = true;
  bool _running = false;
  String _status = '';
  double _progress = 0;
  String _language = 'en-US';

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadSavedKey();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _apiKeyFile.dispose();
    super.dispose();
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<File> _keyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/stt_api_key.txt');
  }

  Future<void> _loadSavedKey() async {
    try {
      final f = await _keyFile();
      if (f.existsSync()) {
        final key = f.readAsStringSync().trim();
        _apiKeyCtrl.text = key;
      }
    } catch (_) {}
  }

  Future<void> _saveKey(String key) async {
    try {
      final f = await _keyFile();
      await f.writeAsString(key.trim());
    } catch (_) {}
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _videoPath = result.files.single.path;
      _srtPath = null;
      _entries = [];
      _status = '';
      _progress = 0;
    });
  }

  Future<void> _generate() async {
    final apiKey = _apiKeyCtrl.text.trim();
    if (_videoPath == null) {
      _showSnack('Pick a video first.');
      return;
    }
    if (apiKey.isEmpty) {
      _showSnack('Enter your Google Speech-to-Text API key.');
      return;
    }

    await _saveKey(apiKey);

    setState(() {
      _running = true;
      _srtPath = null;
      _entries = [];
      _status = 'Starting…';
      _progress = 0;
    });

    try {
      final srtPath = await _service.transcribeVideo(
        videoPath: _videoPath!,
        apiKey: apiKey,
        languageCode: _language,
        onProgress: (s, p) => setState(() {
          _status = s;
          _progress = p;
        }),
      );

      final lines = File(srtPath).readAsStringSync().trim().split('\n\n');
      final entries = lines
          .map(_parseSrtBlock)
          .whereType<SrtEntry>()
          .toList();

      setState(() {
        _srtPath = srtPath;
        _entries = entries;
        _running = false;
        _status = '';
      });
    } catch (e) {
      setState(() {
        _running = false;
        _status = '';
      });
      _showError(e.toString());
    }
  }

  Future<void> _exportSrt() async {
    if (_srtPath == null) return;
    await Share.shareXFiles([XFile(_srtPath!)], text: 'Captions .srt file');
  }

  Future<void> _burnIntoVideo() async {
    if (_videoPath == null || _srtPath == null) return;
    setState(() {
      _running = true;
      _status = 'Burning subtitles…';
      _progress = 0.1;
    });
    try {
      final out = await _service.burnSubtitles(
        videoPath: _videoPath!,
        srtPath: _srtPath!,
        onProgress: (s, p) => setState(() {
          _status = s;
          _progress = p;
        }),
      );
      setState(() {
        _running = false;
        _status = '';
      });
      await Share.shareXFiles([XFile(out)], text: 'Video with burned-in captions');
    } catch (e) {
      setState(() {
        _running = false;
        _status = '';
      });
      _showError('Burn-in failed. Your device may not support subtitle rendering.\n\nExport the .srt file and use it with any media player.\n\n${e.toString()}');
    }
  }

  // ── SRT parsing ─────────────────────────────────────────────────────────────

  SrtEntry? _parseSrtBlock(String block) {
    try {
      final lines = block.trim().split('\n');
      if (lines.length < 3) return null;
      final idx = int.parse(lines[0].trim());
      final times = lines[1].split(' --> ');
      final start = _parseDuration(times[0].trim());
      final end = _parseDuration(times[1].trim());
      final text = lines.skip(2).join('\n');
      return SrtEntry(index: idx, start: start, end: end, text: text);
    } catch (_) {
      return null;
    }
  }

  Duration _parseDuration(String s) {
    // HH:MM:SS,mmm
    final parts = s.split(':');
    final secMs = parts[2].split(',');
    return Duration(
      hours: int.parse(parts[0]),
      minutes: int.parse(parts[1]),
      seconds: int.parse(secMs[0]),
      milliseconds: int.parse(secMs[1]),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Error', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Text(msg,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        foregroundColor: Colors.white,
        title: const Text('Auto Captions',
            style: TextStyle(fontWeight: FontWeight.w600)),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildVideoCard(),
            const SizedBox(height: 12),
            _buildApiKeyCard(),
            const SizedBox(height: 12),
            _buildLanguageCard(),
            const SizedBox(height: 16),
            _buildGenerateButton(),
            if (_running) ...[
              const SizedBox(height: 20),
              _buildProgress(),
            ],
            if (_entries.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildResultActions(),
              const SizedBox(height: 16),
              _buildPreview(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Section widgets ──────────────────────────────────────────────────────────

  Widget _buildVideoCard() {
    return GestureDetector(
      onTap: _running ? null : _pickVideo,
      child: Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _videoPath != null
                ? _kAccent.withValues(alpha: 0.6)
                : Colors.white12,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _videoPath != null
                    ? _kAccent.withValues(alpha: 0.15)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _videoPath != null
                    ? Icons.videocam_rounded
                    : Icons.video_file_outlined,
                color: _videoPath != null ? _kAccent : Colors.white38,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _videoPath != null ? 'Video selected' : 'Select video',
                    style: TextStyle(
                      color:
                          _videoPath != null ? Colors.white : Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_videoPath != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _videoPath!.split('/').last,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyCard() {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key_outlined,
                  color: Colors.white38, size: 16),
              const SizedBox(width: 6),
              const Text('Google Speech-to-Text API Key',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              GestureDetector(
                onTap: () => _showApiKeyHelp(),
                child: const Icon(Icons.help_outline,
                    color: Colors.white24, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: _obscureKey,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'AIza…',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white24,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageCard() {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.language, color: Colors.white38, size: 18),
          const SizedBox(width: 10),
          const Text('Language',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          DropdownButton<String>(
            value: _language,
            dropdownColor: _kCard,
            underline: const SizedBox(),
            icon: const Icon(Icons.expand_more,
                color: Colors.white38, size: 18),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            items: _kLanguages
                .map((l) => DropdownMenuItem(
                      value: l.$2,
                      child: Text(l.$1),
                    ))
                .toList(),
            onChanged: _running
                ? null
                : (v) => setState(() => _language = v ?? _language),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButton() {
    final ready =
        _videoPath != null && _apiKeyCtrl.text.trim().isNotEmpty && !_running;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: ready ? _generate : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kAccent,
          disabledBackgroundColor: Colors.white12,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.closed_caption, color: Colors.white),
        label: Text(
          _running ? 'Processing…' : 'Generate Captions',
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: Colors.white12,
          valueColor: const AlwaysStoppedAnimation(_kAccent),
          borderRadius: BorderRadius.circular(4),
          minHeight: 6,
        ),
        const SizedBox(height: 8),
        Text(_status,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _buildResultActions() {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.file_download_outlined,
            label: 'Export SRT',
            onTap: _running ? null : _exportSrt,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.movie_filter_outlined,
            label: 'Burn into Video',
            onTap: _running ? null : _burnIntoVideo,
            accent: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${_entries.length} subtitle entries',
            style:
                const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        ..._entries.map((e) => _SrtTile(entry: e)),
      ],
    );
  }

  void _showApiKeyHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('How to get an API key',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const SelectableText(
          '1. Go to console.cloud.google.com\n'
          '2. Create a project (or use existing)\n'
          '3. Enable "Cloud Speech-to-Text API"\n'
          '4. Go to APIs & Services → Credentials\n'
          '5. Create API Key\n'
          '6. Copy and paste it here\n\n'
          'Free tier: 60 minutes/month.\n'
          'Audio is sent to Google servers for processing.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: accent
              ? _kAccent.withValues(alpha: 0.15)
              : _kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: accent ? _kAccent.withValues(alpha: 0.5) : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: accent ? _kAccent : Colors.white54, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  color: accent ? _kAccent : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }
}

class _SrtTile extends StatelessWidget {
  final SrtEntry entry;
  const _SrtTile({required this.entry});

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms =
        (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return '$m:$s.$ms';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_fmt(entry.start)} ',
            style: const TextStyle(
                color: _kAccent, fontSize: 10, fontFamily: 'monospace'),
          ),
          Expanded(
            child: Text(entry.text,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
