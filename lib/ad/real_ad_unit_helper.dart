import 'dart:io';

class RealAdUnitHelper {


  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-9774025861505870/9642886068';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-9774025861505870/2118896878';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-9774025861505870/7617962728';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/5224354917';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get appOpenAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/9257395921';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-9774025861505870/9536020766';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get nativeAdUnitId {
    if (Platform.isAndroid) {
      // TODO: Replace with your real Android native ad unit ID from AdMob console
      return 'ca-app-pub-9774025861505870/XXXXXXXXXX';
    } else if (Platform.isIOS) {
      // TODO: Replace with your real iOS native ad unit ID from AdMob console
      return 'ca-app-pub-9774025861505870/XXXXXXXXXX';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
}