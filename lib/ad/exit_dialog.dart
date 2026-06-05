import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_helper.dart';

class ExitConfirmationDialog extends StatefulWidget {
  const ExitConfirmationDialog({super.key});

  @override
  State<ExitConfirmationDialog> createState() => _ExitConfirmationDialogState();
}

class _ExitConfirmationDialogState extends State<ExitConfirmationDialog> {
  NativeAd? _nativeAd;
  bool _adLoaded = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _loadNativeAd();
    }
  }

  void _loadNativeAd() {
    final ad = NativeAd(
      adUnitId: AdHelper.nativeAdUnitId,
      factoryId: 'exitDialogAd',
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _adLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
      request: const AdRequest(),
    );
    ad.load().then((_) {
      if (mounted) {
        setState(() => _nativeAd = ad);
      } else {
        ad.dispose();
      }
    });
    _nativeAd = ad;
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF12122A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirm to exit?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildAdSection(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: 'OK',
                    textColor: const Color(0xFFFF6B6B),
                    backgroundColor: const Color(0xFF3D1515),
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DialogButton(
                    label: 'Cancel',
                    textColor: Colors.white,
                    backgroundColor: const Color(0xFFE74C3C),
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdSection() {
    if (!Platform.isAndroid) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3A),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: _adLoaded && _nativeAd != null
          ? SizedBox(
              height: 360,
              child: AdWidget(ad: _nativeAd!),
            )
          : const SizedBox(
              height: 360,
              child: _AdShimmer(),
            ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.textColor,
    required this.backgroundColor,
    required this.onTap,
  });

  final String label;
  final Color textColor;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AdShimmer extends StatefulWidget {
  const _AdShimmer();

  @override
  State<_AdShimmer> createState() => _AdShimmerState();
}

class _AdShimmerState extends State<_AdShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = 0.3 + _anim.value * 0.4;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBox(opacity, double.infinity, 16, radius: 4),
              const SizedBox(height: 8),
              _shimmerBox(opacity, double.infinity, 180, radius: 8),
              const SizedBox(height: 12),
              Row(
                children: [
                  _shimmerBox(opacity, 52, 52, radius: 8),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _shimmerBox(opacity, double.infinity, 14, radius: 4),
                        const SizedBox(height: 6),
                        _shimmerBox(opacity, 120, 12, radius: 4),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _shimmerBox(opacity, double.infinity, 48, radius: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _shimmerBox(double opacity, double w, double h, {double radius = 4}) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A4A),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
