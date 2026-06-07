import 'package:shared_preferences/shared_preferences.dart';

/// Persistent app-wide settings backed by SharedPreferences.
/// Call [AppSettings.load()] once at app start (or lazily on first use).
class AppSettings {
  AppSettings._();
  static AppSettings? _instance;

  static const _kResolution   = 'settings_resolution_index';  // 0-4
  static const _kFps          = 'settings_fps_index';         // 0-4
  static const _kAutoSave     = 'settings_auto_save';
  static const _kNotifications = 'settings_notifications';

  late SharedPreferences _prefs;

  // ── Resolution: 0=480p  1=720p  2=1080p  3=2K  4=4K ─────────────────────
  static const List<String> resolutionLabels = ['480p', '720p', '1080p', '2K', '4K'];
  // ── Frame rate: 0=24  1=25  2=30  3=50  4=60 ─────────────────────────────
  static const List<String> fpsLabels = ['24', '25', '30', '50', '60'];

  int  get defaultResolutionIndex => _prefs.getInt(_kResolution) ?? 2;   // 1080p
  int  get defaultFpsIndex        => _prefs.getInt(_kFps) ?? 2;          // 30 fps
  bool get autoSaveToGallery      => _prefs.getBool(_kAutoSave) ?? true;
  bool get notificationsEnabled   => _prefs.getBool(_kNotifications) ?? false;

  String get defaultResolutionLabel => resolutionLabels[defaultResolutionIndex];
  String get defaultFpsLabel        => fpsLabels[defaultFpsIndex];

  Future<void> setDefaultResolutionIndex(int v) =>
      _prefs.setInt(_kResolution, v.clamp(0, 4));

  Future<void> setDefaultFpsIndex(int v) =>
      _prefs.setInt(_kFps, v.clamp(0, 4));

  Future<void> setAutoSaveToGallery(bool v) =>
      _prefs.setBool(_kAutoSave, v);

  Future<void> setNotificationsEnabled(bool v) =>
      _prefs.setBool(_kNotifications, v);

  // ── Singleton access ──────────────────────────────────────────────────────

  static Future<AppSettings> load() async {
    if (_instance != null) return _instance!;
    final inst = AppSettings._();
    inst._prefs = await SharedPreferences.getInstance();
    _instance = inst;
    return inst;
  }

  /// Returns the already-loaded instance.
  /// Throws if [load()] has not been called yet.
  static AppSettings get instance {
    assert(_instance != null,
        'AppSettings.load() must be called before accessing AppSettings.instance');
    return _instance!;
  }
}
