import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad/app_open_ad_manager.dart';
import 'screen/export_progress/export_progress_screen.dart';
import 'screen/home/home_screen.dart';
import 'service/app_settings.dart';
import 'service/export_progress_state.dart';
import 'service/export_service_manager.dart';
import 'update/in_app_update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await MobileAds.instance.initialize();
  await AppSettings.load();
  await InAppUpdateService.checkAndUpdate();
  ExportServiceManager.initialize();
  // Preload the first App Open Ad immediately after SDK init.
 // temporary commented:  AppOpenAdManager.instance.loadAd();
  runApp(const VideoEditorApp());
}

/// Global navigator key used to push screens from outside the widget tree
/// (e.g. when the user taps the export progress notification).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class VideoEditorApp extends StatefulWidget {
  const VideoEditorApp({super.key});

  @override
  State<VideoEditorApp> createState() => _VideoEditorAppState();
}

class _VideoEditorAppState extends State<VideoEditorApp>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;

  /// Minimum time the app must be backgrounded before showing an App Open Ad.
  /// This prevents the ad from showing when the user briefly opens the
  /// notification bar and dismisses it.
  static const _minBackgroundDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Open the export progress screen when the user taps the notification.
    // addPostFrameCallback defers navigation until after the current frame,
    // ensuring the navigator is fully active after the app resumes.
    ExportServiceManager.notificationTaps.listen((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ExportProgressState.instance.isExporting.value) return;
        navigatorKey.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => const ExportProgressScreen(),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called whenever the app lifecycle state changes.
  /// Show the App Open Ad when the app returns to the foreground,
  /// but only if it was backgrounded for longer than [_minBackgroundDuration]
  /// and an export is not currently in progress.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final paused = _pausedAt;
      if (paused != null &&
          DateTime.now().difference(paused) >= _minBackgroundDuration &&
          !ExportServiceManager.isExporting) {
        AppOpenAdManager.instance.showAdIfAvailable();
      }
      _pausedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Video Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00C8FF),
          secondary: Color(0xFFFF4D4D),
          surface: Color(0xFF111E2F),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D1623),
      ),
      home: const HomeScreen(),
    );
  }
}
