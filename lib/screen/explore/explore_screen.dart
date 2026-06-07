import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ad/app_open_ad_manager.dart';

// ── App entry model ──────────────────────────────────────────────────────────

class _AppEntry {
  final String name;
  final String subtitle;
  final String packageId; // Play Store package name
  final Color bannerColor; // placeholder gradient colour
  final Color iconColor;

  const _AppEntry({
    required this.name,
    required this.subtitle,
    required this.packageId,
    required this.bannerColor,
    required this.iconColor,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  App list — update packageId per app when ready.
// ─────────────────────────────────────────────────────────────────────────────
const _kApps = [
  _AppEntry(
    name: 'SoundHub: Music Player & Advanced Editor',
    subtitle: 'Advanced Music Player & Editor',
    packageId: 'com.soundhub.rancic',
    bannerColor: Color(0xFF7BBFCF),
    iconColor: Color(0xFF1565C0),
  ),
  // _AppEntry(
  //   name: 'PicInk - AI Tattoo Generator',
  //   subtitle: 'Design, Try On & Edit',
  //   packageId: 'com.picink.tattoo',
  //   bannerColor: Color(0xFFD4A47A),
  //   iconColor: Color(0xFF7B1FA2),
  // ),
  // _AppEntry(
  //   name: 'CapTune - Subtitle Generator',
  //   subtitle: 'Auto Captions & Subtitles',
  //   packageId: 'com.captune.subtitles',
  //   bannerColor: Color(0xFF2E2E3E),
  //   iconColor: Color(0xFF2E7D32),
  // ),
  // _AppEntry(
  //   name: 'ArtFlow - AI Art Maker',
  //   subtitle: 'Generate & Edit AI Artwork',
  //   packageId: 'com.artflow.aiart',
  //   bannerColor: Color(0xFF6A3FA0),
  //   iconColor: Color(0xFFE65100),
  // ),
  // _AppEntry(
  //   name: 'BeatSync - Music Video Maker',
  //   subtitle: 'Sync Beats to Video Clips',
  //   packageId: 'com.beatsync.musicvideo',
  //   bannerColor: Color(0xFF1A3A5C),
  //   iconColor: Color(0xFF00838F),
  // ),
];

// ── Screen ───────────────────────────────────────────────────────────────────

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Explore',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _kApps.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) => _AppCard(app: _kApps[i]),
      ),
    );
  }
}

// ── App card ─────────────────────────────────────────────────────────────────

class _AppCard extends StatelessWidget {
  final _AppEntry app;
  const _AppCard({required this.app});

  Future<void> _openPlayStore(BuildContext context) async {
    AppOpenAdManager.instance.suppressNextResume();
    // Try market:// first (opens Play Store app); fall back to https.
    final market = Uri.parse('market://details?id=${app.packageId}');
    final web = Uri.parse(
        'https://play.google.com/store/apps/details?id=${app.packageId}');

    bool launched = false;
    try {
      launched = await launchUrl(market,
          mode: LaunchMode.externalApplication);
    } catch (_) {}

    if (!launched) {
      try {
        await launchUrl(web, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Play Store')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openPlayStore(context),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBanner(),
            _buildInfoRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    // Gradient placeholder until real banner image is added.
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            app.bannerColor,
            app.bannerColor.withValues(alpha: 0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.white24, size: 52),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        children: [
          // App icon placeholder
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: app.iconColor,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.apps_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          // Name + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  app.subtitle,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // "Get" button
          GestureDetector(
            onTap: () => _openPlayStore(context),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 22, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF2E2E2E),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text(
                'Get',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
