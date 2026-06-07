import 'package:video_editor/ad/test_ad_unit_helper.dart';
import 'real_ad_unit_helper.dart';

class AdHelper {
  static bool debug = true;

  static String get bannerAdUnitId {
    if (debug) {
      return TestAdUnitHelper.bannerAdUnitId;
    } else {
      return RealAdUnitHelper.bannerAdUnitId;
    }
  }

  static String get interstitialAdUnitId {
    if (debug) {
      return TestAdUnitHelper.interstitialAdUnitId;
    } else {
      return RealAdUnitHelper.interstitialAdUnitId;
    }
  }

  static String get rewardedAdUnitId {
    if (debug) {
      return TestAdUnitHelper.rewardedAdUnitId;
    } else {
      return RealAdUnitHelper.rewardedAdUnitId;
    }
  }

  static String get appOpenAdUnitId {
    if (debug) {
      return TestAdUnitHelper.appOpenAdUnitId;
    } else {
      return RealAdUnitHelper.appOpenAdUnitId;
    }
  }

  static String get nativeAdUnitId {
    if (debug) {
      return TestAdUnitHelper.nativeAdUnitId;
    } else {
      return RealAdUnitHelper.nativeAdUnitId;
    }
  }
}