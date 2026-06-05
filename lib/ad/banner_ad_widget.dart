import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shimmer/shimmer.dart';

import 'ad_helper.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _adLoaded = false;

  // Standard banner size: 320x50
  static const double _bannerHeight = 50;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final banner = BannerAd(
      adUnitId: AdHelper.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _adLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BannerAd failed to load: $error');
          ad.dispose();
        },
      ),
    );
    banner.load();
    _bannerAd = banner;
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _bannerHeight,
      child: _adLoaded && _bannerAd != null
          ? AdWidget(ad: _bannerAd!)
          : _buildShimmer(),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF1A2A3D),
      highlightColor: const Color(0xFF2A3F5A),
      child: Container(
        height: _bannerHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF1A2A3D),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
