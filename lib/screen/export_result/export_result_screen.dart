import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../ad/banner_ad_widget.dart';
import '../../service/app_settings.dart';

class ExportResultScreen extends StatefulWidget {
  final String videoPath;

  const ExportResultScreen({
    super.key,
    required this.videoPath,
  });

  @override
  State<ExportResultScreen> createState() => _ExportResultScreenState();
}

class _ExportResultScreenState extends State<ExportResultScreen>
    with WidgetsBindingObserver {

  static const _platform = MethodChannel('com.video.rd.editor/export_service');

  // ── Video playback ──────────────────────────────────────────────────────
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _initError = false;

  // ── Seek state ──────────────────────────────────────────────────────────
  bool _isSeeking = false;
  double _seekValue = 0.0;

  // ── Format detection ────────────────────────────────────────────────────
  late final bool _isGif;

  static const Color _bg = Color(0xFF0D1623);
  static const Color _surface = Color(0xFF111E2F);
  static const Color _primary = Color(0xFF00C8FF);
  static const Color _textMuted = Color(0xFF8A9BB5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isGif = widget.videoPath.toLowerCase().endsWith('.gif');

    if (!_isGif) {
      _controller = VideoPlayerController.file(File(widget.videoPath))
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() => _initialized = true);
          _controller!.setLooping(true);
          _controller!.play();
          if (AppSettings.instance.autoSaveToGallery) {
            _saveToGallery(silent: true);
          }
        }).catchError((e) {
          debugPrint('Video init error: $e');
          if (mounted) setState(() => _initError = true);
        });
      _controller!.addListener(_onControllerUpdate);
    } else {
      if (AppSettings.instance.autoSaveToGallery) {
        _saveToGallery(silent: true);
      }
    }
  }

  void _onControllerUpdate() {
    if (mounted && !_isSeeking) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  // ── Gallery save ────────────────────────────────────────────────────────

  Future<void> _saveToGallery({bool silent = false}) async {
    try {
      if (_isGif) {
        await Gal.putImage(widget.videoPath, album: 'Video Editor');
      } else {
        await Gal.putVideo(widget.videoPath, album: 'Video Editor');
      }
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to gallery'),
            backgroundColor: Color(0xFF2CB67D),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Gallery save error: $e');
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save to gallery: $e',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Share ───────────────────────────────────────────────────────────────

  String get _mimeType {
    final ext = widget.videoPath.split('.').last.toLowerCase();
    return switch (ext) {
      'webm' => 'video/webm',
      'mov' => 'video/quicktime',
      'mkv' => 'video/x-matroska',
      'gif' => 'image/gif',
      _ => 'video/mp4',
    };
  }

  /// Share directly to a specific app via Android explicit Intent.
  /// Falls back to generic system share sheet if the app is not installed.
  Future<void> _shareToApp(String packageName) async {
    try {
      final installed = await _platform.invokeMethod<bool>('shareToApp', {
        'filePath': widget.videoPath,
        'package': packageName,
        'mimeType': _mimeType,
      });
      if (installed != true) {
        // App not installed — fall back to generic share
        await _shareGeneric();
      }
    } catch (_) {
      await _shareGeneric();
    }
  }

  Future<void> _shareGeneric() async {
    await Share.shareXFiles(
      [XFile(widget.videoPath, mimeType: _mimeType)],
      subject: 'My video',
    );
  }

  Future<void> _shareToInstagramDirect() async {
    try {
      final installed = await _platform.invokeMethod<bool>('shareToInstagramDirect', {
        'filePath': widget.videoPath,
        'mimeType': _mimeType,
      });
      if (installed != true) {
        await _shareGeneric();
      }
    } catch (_) {
      await _shareGeneric();
    }
  }

  Future<void> _shareToInstagramStory() async {
    try {
      final installed = await _platform.invokeMethod<bool>('shareToInstagramStory', {
        'filePath': widget.videoPath,
        'mimeType': _mimeType,
      });
      if (installed != true) {
        await _shareGeneric();
      }
    } catch (_) {
      await _shareGeneric();
    }
  }

  Future<void> _showInstagramPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share to Instagram',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _igOption(
                ctx: ctx,
                icon: Icons.grid_on_rounded,
                label: 'Feed',
                desc: 'Post as a regular video on your feed',
                onTap: () {
                  Navigator.pop(ctx);
                  _shareToApp('com.instagram.android');
                },
              ),
              const SizedBox(height: 10),
              _igOption(
                ctx: ctx,
                icon: Icons.auto_stories_rounded,
                label: 'Story',
                desc: 'Share directly to your Instagram Story',
                onTap: () {
                  Navigator.pop(ctx);
                  _shareToInstagramStory();
                },
              ),
              const SizedBox(height: 10),
              _igOption(
                ctx: ctx,
                icon: Icons.send_rounded,
                label: 'Direct Message',
                desc: 'Send video to someone via Instagram DM',
                onTap: () {
                  Navigator.pop(ctx);
                  _shareToInstagramDirect();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _igOption({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required String desc,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFFCB045)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(desc,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Discard ─────────────────────────────────────────────────────────────

  Future<void> _discard() async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Discard file?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'The exported file will be deleted. This cannot be undone.',
          style: TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF4D4D)),
            child: const Text('Discard',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final file = File(widget.videoPath);
      if (await file.exists()) await file.delete();
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _positionFraction {
    final ctrl = _controller;
    if (ctrl == null) return 0;
    final dur = ctrl.value.duration.inMicroseconds;
    if (dur == 0) return 0.0;
    return (ctrl.value.position.inMicroseconds / dur).clamp(0.0, 1.0);
  }

  void _togglePlay() {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
    setState(() {});
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: Colors.white,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isGif ? 'Export Preview (GIF)' : 'Export Preview',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt_rounded, size: 22),
            color: _primary,
            onPressed: () => _saveToGallery(silent: false),
            tooltip: 'Save to gallery',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildPreview()),
          _buildSharePanel(),
          _buildDiscardButton(),
          const SafeArea(
            top: false,
            child: BannerAdWidget(),
          ),
        ],
      ),
    );
  }

  // ── Preview ──────────────────────────────────────────────────────────────

  Widget _buildPreview() {
    return Container(
      color: Colors.black,
      child: _isGif ? _buildGifPreview() : _buildVideoPreview(),
    );
  }

  Widget _buildGifPreview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Image.file(
          File(widget.videoPath),
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('GIF',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPreview() {
    final ctrl = _controller;

    if (_initError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            const Text('Could not play video',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _shareGeneric,
              child: const Text('Share anyway',
                  style: TextStyle(color: _primary)),
            ),
          ],
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        if (_initialized && ctrl != null)
          AspectRatio(
            aspectRatio: ctrl.value.aspectRatio,
            child: VideoPlayer(ctrl),
          )
        else
          const CircularProgressIndicator(color: _primary, strokeWidth: 2),

        // Play/pause overlay
        if (_initialized && ctrl != null)
          GestureDetector(
            onTap: _togglePlay,
            behavior: HitTestBehavior.translucent,
            child: AnimatedOpacity(
              opacity: !ctrl.value.isPlaying ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 40),
              ),
            ),
          ),

        // Time labels
        if (_initialized && ctrl != null)
          Positioned(
            bottom: 36,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _timeChip(_fmt(_isSeeking
                    ? Duration(
                        microseconds: (_seekValue *
                                ctrl.value.duration.inMicroseconds)
                            .round())
                    : ctrl.value.position)),
                const Spacer(),
                _timeChip(_fmt(ctrl.value.duration)),
              ],
            ),
          ),

        // Seek slider
        if (_initialized && ctrl != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildSeekBar(ctrl),
          ),
      ],
    );
  }

  Widget _buildSeekBar(VideoPlayerController ctrl) {
    final value = _isSeeking ? _seekValue : _positionFraction;

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        thumbColor: _primary,
        activeTrackColor: _primary,
        inactiveTrackColor: const Color(0xFF2A3A50),
        overlayColor: _primary.withValues(alpha: 0.25),
        trackShape: const RectangularSliderTrackShape(),
      ),
      child: Slider(
        value: value,
        min: 0,
        max: 1,
        onChangeStart: (_) {
          setState(() {
            _isSeeking = true;
            _seekValue = _positionFraction;
          });
          ctrl.pause();
        },
        onChanged: (v) => setState(() => _seekValue = v),
        onChangeEnd: (v) async {
          final totalUs = ctrl.value.duration.inMicroseconds;
          await ctrl.seekTo(Duration(microseconds: (v * totalUs).round()));
          if (mounted) {
            setState(() => _isSeeking = false);
            ctrl.play();
          }
        },
      ),
    );
  }

  Widget _timeChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
      );

  // ── Share panel ──────────────────────────────────────────────────────────

  Widget _buildSharePanel() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 20),
            child: Text(
              'Share to',
              style: TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          // 2-row horizontally scrollable grid
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 10, right: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: WhatsApp, Instagram, TikTok, Viber, Messenger, Telegram
                Row(
                  children: [
                    _appShareButton(
                      label: 'WhatsApp', icon: Icons.chat_rounded,
                      color: const Color(0xFF25D366), size: 54,
                      onTap: () => _shareToApp('com.whatsapp'),
                    ),
                    _appShareButton(
                      label: 'Instagram', icon: Icons.camera_alt_rounded,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFFCB045)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      size: 54, onTap: _showInstagramPicker,
                    ),
                    _appShareButton(
                      label: 'TikTok', icon: Icons.music_note_rounded,
                      color: const Color(0xFF010101), iconColor: const Color(0xFFFE2C55),
                      borderColor: const Color(0xFF2A2A2A), size: 54,
                      onTap: () => _shareToApp('com.zhiliaoapp.musically'),
                    ),
                    _appShareButton(
                      label: 'Viber', icon: Icons.phone_in_talk_rounded,
                      color: const Color(0xFF7360F2), size: 54,
                      onTap: () => _shareToApp('com.viber.voip'),
                    ),
                    _appShareButton(
                      label: 'Messenger', icon: Icons.messenger_rounded,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0095F6), Color(0xFFA334FA)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      size: 54, onTap: () => _shareToApp('com.facebook.orca'),
                    ),
                    _appShareButton(
                      label: 'Telegram', icon: Icons.send_rounded,
                      color: const Color(0xFF2CA5E0), size: 54,
                      onTap: () => _shareToApp('org.telegram.messenger'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Row 2: Snapchat, X, Discord, Drive, More
                Row(
                  children: [
                    _appShareButton(
                      label: 'Snapchat', icon: Icons.camera_enhance_rounded,
                      color: const Color(0xFFFFFC00), iconColor: Colors.black, size: 54,
                      onTap: () => _shareToApp('com.snapchat.android'),
                    ),
                    _appShareButton(
                      label: 'X', icon: Icons.close_rounded,
                      color: Colors.black, borderColor: const Color(0xFF333333), size: 54,
                      onTap: () => _shareToApp('com.twitter.android'),
                    ),
                    _appShareButton(
                      label: 'Discord', icon: Icons.headset_mic_rounded,
                      color: const Color(0xFF5865F2), size: 54,
                      onTap: () => _shareToApp('com.discord'),
                    ),
                    _appShareButton(
                      label: 'Drive', icon: Icons.cloud_upload_rounded,
                      color: const Color(0xFF4285F4), size: 54,
                      onTap: () => _shareToApp('com.google.android.apps.docs'),
                    ),
                    _appShareButton(
                      label: 'More', icon: Icons.more_horiz_rounded,
                      color: const Color(0xFF2A3A50), size: 54,
                      onTap: _shareGeneric,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _appShareButton({
    required String label,
    required IconData icon,
    Color? color,
    Color? iconColor,
    Color? borderColor,
    Gradient? gradient,
    required VoidCallback onTap,
    double size = 62,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
        children: [
          Container(
            width: size, height: size,
            decoration: BoxDecoration(
              color: gradient == null ? color : null,
              gradient: gradient,
              borderRadius: BorderRadius.circular(size * 0.29),
              border: borderColor != null
                  ? Border.all(color: borderColor, width: 1.5)
                  : null,
            ),
            child: Icon(icon, color: iconColor ?? Colors.white, size: size * 0.42),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
      ),
    );
  }

  // ── Discard button ───────────────────────────────────────────────────────

  Widget _buildDiscardButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _discard,
          icon: const Icon(Icons.delete_outline_rounded,
              size: 18, color: Color(0xFFFF4D4D)),
          label: const Text('Discard',
              style: TextStyle(
                  color: Color(0xFFFF4D4D),
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Color(0xFF3A1E22), width: 1.5),
            backgroundColor: const Color(0xFF1A0F10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }
}
