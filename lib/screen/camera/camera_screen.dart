import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_result_preview_screen.dart';
import '../media_picker/media_picker_screen.dart';

class CameraScreen extends StatefulWidget {
  /// Optional callback for callers that want the captured file returned to
  /// them directly (e.g. collage editor) instead of the default flow of
  /// opening the standalone VideoEditorScreen.
  final void Function(PickedMediaFile)? onCapture;

  const CameraScreen({super.key, this.onCapture});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _isVideoMode = true;
  bool _isRecording = false;
  FlashMode _flashMode = FlashMode.off;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  bool _initialized = false;
  bool _showSwipeHint = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initCameras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    if (state == AppLifecycleState.paused) {
      // App is truly going to background — stop recording if active, then dispose
      _recordingTimer?.cancel();
      if (mounted) {
        setState(() {
          _initialized = false;
          _isRecording = false;
          _recordingSeconds = 0;
        });
      }
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setupCamera(_cameras[_cameraIndex]);
    }
    // AppLifecycleState.inactive is a transient state (screenshot, notification
    // shade, incoming call overlay) — do nothing so recording is not interrupted.
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _errorMessage = 'No cameras found on this device.');
        return;
      }
      // Prefer back camera as default
      final backIdx = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back);
      _cameraIndex = backIdx >= 0 ? backIdx : 0;
      await _setupCamera(_cameras[_cameraIndex]);
    } on CameraException catch (e) {
      setState(() => _errorMessage = 'Camera error: ${e.description}');
    }
  }

  Future<void> _setupCamera(CameraDescription camera) async {
    final old = _controller;
    if (old != null) {
      await old.dispose();
    }

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;

    try {
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      if (mounted) {
        setState(() {
          _initialized = true;
          _errorMessage = null;
        });
      }
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not initialize camera: ${e.description}');
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _isRecording) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _initialized = false);
    await _setupCamera(_cameras[_cameraIndex]);
  }

  Future<void> _toggleFlash() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isRecording) return;

    FlashMode next;
    switch (_flashMode) {
      case FlashMode.off:
        next = FlashMode.torch;
        break;
      case FlashMode.torch:
        next = FlashMode.auto;
        break;
      default:
        next = FlashMode.off;
    }

    try {
      await ctrl.setFlashMode(next);
      setState(() => _flashMode = next);
    } on CameraException catch (_) {}
  }

  Future<void> _capturePhoto() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isRecording) return;

    try {
      final file = await ctrl.takePicture();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CameraResultPreviewScreen(
            filePath: file.path,
            isVideo: false,
            onCapture: widget.onCapture,
          ),
          fullscreenDialog: true,
        ),
      );
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture photo: ${e.description}')),
        );
      }
    }
  }

  Future<void> _toggleRecording() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    if (_isRecording) {
      _recordingTimer?.cancel();
      try {
        final file = await ctrl.stopVideoRecording();
        if (mounted) {
          setState(() {
            _isRecording = false;
            _recordingSeconds = 0;
          });
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CameraResultPreviewScreen(
                filePath: file.path,
                isVideo: true,
                onCapture: widget.onCapture,
              ),
              fullscreenDialog: true,
            ),
          );
        }
      } on CameraException catch (e) {
        if (mounted) {
          setState(() => _isRecording = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Recording failed: ${e.description}')),
          );
        }
      }
    } else {
      try {
        await ctrl.startVideoRecording();
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _recordingSeconds++);
        });
        setState(() {
          _isRecording = true;
          _showSwipeHint = false;
        });
      } on CameraException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start recording: ${e.description}')),
          );
        }
      }
    }
  }

  void _onRecordButtonTap() {
    if (_isVideoMode) {
      _toggleRecording();
    } else {
      _capturePhoto();
    }
  }

  IconData get _flashIconData {
    switch (_flashMode) {
      case FlashMode.torch:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      default:
        return Icons.flash_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ────────────────────────────────────────────────
          _buildCameraPreview(),

          // ── Top bar ───────────────────────────────────────────────────────
          Positioned(
            top: topPad + 4,
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),

          // ── Right sidebar ─────────────────────────────────────────────────
          if (!_isRecording)
            Positioned(
              right: 8,
              top: topPad + 64,
              child: _buildRightSidebar(),
            ),

          // ── Swipe hint ────────────────────────────────────────────────────
          if (_showSwipeHint && _initialized && !_isRecording)
            Center(child: _buildSwipeHint()),

          // Recording timer is embedded in top bar when recording (see _buildTopBar)

          // ── Bottom controls ───────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomControls(botPad),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined,
                  color: Colors.white38, size: 64),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized || _controller == null) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
              color: Colors.white54, strokeWidth: 2),
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _showSwipeHint = false),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.previewSize?.height ?? 1,
            height: _controller!.value.previewSize?.width ?? 1,
            child: CameraPreview(_controller!),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 26),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          // Center: recording timer OR add music pill
          if (_isRecording)
            _buildRecordingTimer()
          else
            GestureDetector(
              onTap: () {},
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_note, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Add music',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          const Spacer(),
          // Flip — hidden while recording
          if (!_isRecording)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios_outlined,
                  color: Colors.white, size: 26),
              onPressed: _flipCamera,
            )
          else
            const SizedBox(width: 48), // keep spacing balanced
        ],
      ),
    );
  }

  Widget _buildRightSidebar() {
    return Column(
      children: [
        _SidebarButton(
          icon: Icons.flip_camera_ios_outlined,
          label: 'Flip',
          onTap: _flipCamera,
        ),
        const SizedBox(height: 20),
        _SidebarButton(
          icon: _flashIconData,
          label: 'Flash',
          onTap: _toggleFlash,
          highlight: _flashMode != FlashMode.off,
          badge: _flashMode == FlashMode.auto ? 'A' : null,
        ),
        const SizedBox(height: 20),
        _SidebarButton(
          icon: Icons.crop_free,
          label: '9:16',
          onTap: () {},
        ),
        const SizedBox(height: 20),
        _SidebarButton(
          icon: Icons.timer_outlined,
          label: 'Timer',
          onTap: () {},
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () {},
          child: const Column(
            children: [
              Text(
                '1x',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 2),
              Text(
                'Speed',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSwipeHint() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 80,
          height: 80,
          child: Icon(Icons.swipe, color: Colors.white, size: 64),
        ),
        const SizedBox(height: 12),
        const Text(
          'Swipe to change filter',
          style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildRecordingTimer() {
    final mins = _recordingSeconds ~/ 60;
    final secs = _recordingSeconds % 60;
    return Center(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFCC0000),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls(double botPad) {
    return Container(
      padding: EdgeInsets.only(bottom: botPad + 16, top: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
          stops: const [0.0, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Filter / Effect / Record
          SizedBox(
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Left: Filter + Effect — hidden while recording
                if (!_isRecording)
                  Positioned(
                    left: 20,
                    child: Row(
                      children: [
                        _BottomIconButton(
                            icon: Icons.filter_outlined, label: 'Filter'),
                        const SizedBox(width: 20),
                        _BottomIconButton(
                            icon: Icons.auto_awesome_outlined, label: 'Effect'),
                      ],
                    ),
                  ),
                // Center: record button
                GestureDetector(
                  onTap: _onRecordButtonTap,
                  child: _RecordButton(
                    isRecording: _isRecording,
                    isVideoMode: _isVideoMode,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Mode tabs
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ModeTab(
                label: 'Video',
                isSelected: _isVideoMode,
                onTap: _isRecording
                    ? null
                    : () => setState(() => _isVideoMode = true),
              ),
              const SizedBox(width: 32),
              _ModeTab(
                label: 'Photo',
                isSelected: !_isVideoMode,
                onTap: _isRecording
                    ? null
                    : () => setState(() => _isVideoMode = false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Sidebar button ────────────────────────────────────────────────────────────

class _SidebarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlight;
  final String? badge;

  const _SidebarButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.highlight = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.35),
            ),
            child: Icon(
              icon,
              color: highlight ? const Color(0xFFF5A623) : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ── Bottom icon button ────────────────────────────────────────────────────────

class _BottomIconButton extends StatelessWidget {
  final IconData icon;
  final String label;

  const _BottomIconButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

// ── Record button ─────────────────────────────────────────────────────────────

class _RecordButton extends StatelessWidget {
  final bool isRecording;
  final bool isVideoMode;

  const _RecordButton({required this.isRecording, required this.isVideoMode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isRecording
              ? Colors.white54
              : Colors.white.withValues(alpha: 0.85),
          width: 3.5,
        ),
      ),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: isRecording ? 30 : 62,
          height: isRecording ? 30 : 62,
          decoration: BoxDecoration(
            color: isVideoMode ? const Color(0xFFD32F2F) : Colors.white,
            borderRadius: BorderRadius.circular(isRecording ? 8 : 31),
          ),
        ),
      ),
    );
  }
}

// ── Mode tab ──────────────────────────────────────────────────────────────────

class _ModeTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  const _ModeTab(
      {required this.label, required this.isSelected, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontSize: 15,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 4),
          if (isSelected)
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            )
          else
            const SizedBox(height: 5),
        ],
      ),
    );
  }
}
