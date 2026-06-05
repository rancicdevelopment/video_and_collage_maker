import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_helper.dart';

/// Manages loading and showing App Open Ads.
/// Handles both cold start and foreground (resume) scenarios.
class AppOpenAdManager {
  static final AppOpenAdManager instance = AppOpenAdManager._internal();
  AppOpenAdManager._internal();

  /// Maximum duration an ad can be cached before it expires.
  final Duration maxCacheDuration = const Duration(hours: 4);

  DateTime? _appOpenLoadTime;
  AppOpenAd? _appOpenAd;
  bool _isShowingAd = false;
  bool _isLoadingAd = false;

  /// Set to true before any action that temporarily backgrounds the app
  /// (e.g. system permission dialogs) so the next resume doesn't show an ad.
  /// Auto-clears after one suppressed resume.
  bool _suppressNextResume = false;

  void suppressNextResume() => _suppressNextResume = true;

  bool get isAdAvailable => _appOpenAd != null;

  bool get _isAdExpired {
    if (_appOpenLoadTime == null) return true;
    return DateTime.now().subtract(maxCacheDuration).isAfter(_appOpenLoadTime!);
  }

  /// Load an [AppOpenAd]. No-ops if already loading or a fresh ad is cached.
  void loadAd() {
    if (_isLoadingAd) return;
    if (isAdAvailable && !_isAdExpired) return;

    _isLoadingAd = true;

    AppOpenAd.load(
      adUnitId: AdHelper.appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[AppOpenAd] Loaded.');
          _appOpenLoadTime = DateTime.now();
          _appOpenAd = ad;
          _isLoadingAd = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AppOpenAd] Failed to load: $error');
          _isLoadingAd = false;
        },
      ),
    );
  }

  /// Show the ad if one is available and not expired.
  /// Triggers a reload if no ad is ready.
  void showAdIfAvailable() {
    if (_suppressNextResume) {
      _suppressNextResume = false;
      debugPrint('[AppOpenAd] Resume suppressed (system dialog).');
      return;
    }
    if (_isShowingAd) {
      debugPrint('[AppOpenAd] Already showing an ad.');
      return;
    }
    if (!isAdAvailable || _isAdExpired) {
      debugPrint('[AppOpenAd] No fresh ad available — loading a new one.');
      if (_appOpenAd != null) {
        _appOpenAd!.dispose();
        _appOpenAd = null;
      }
      loadAd();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAd = true;
        debugPrint('[AppOpenAd] Showing.');
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[AppOpenAd] Failed to show: $error');
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadAd();
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('[AppOpenAd] Dismissed.');
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadAd(); // preload next ad
      },
    );

    _appOpenAd!.show();
  }
}
