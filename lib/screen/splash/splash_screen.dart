import 'package:flutter/material.dart';

import '../home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Logo: scale + fade
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  // App name: slide up + fade
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;

  // Tagline: fade in
  late final Animation<double> _tagOpacity;

  // Full screen fade-out before navigating
  late final Animation<double> _screenFade;

  static const _bg = Color(0xFF0E1428);

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    // ── Logo ────────────────────────────────────────────────────────────────
    // Scale: 0–600ms with elasticOut bounce
    _logoScale = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.30, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.15, curve: Curves.easeIn),
      ),
    );

    // ── App name ─────────────────────────────────────────────────────────────
    // Appears after logo settles (300ms), slides up from 24px below
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.28, 0.50, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.28, 0.52, curve: Curves.easeOutCubic),
      ),
    );

    // ── Tagline ───────────────────────────────────────────────────────────────
    _tagOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.46, 0.65, curve: Curves.easeOut),
      ),
    );

    // ── Screen fade-out ───────────────────────────────────────────────────────
    // Fades entire screen to black in the last 250ms
    _screenFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.88, 1.0, curve: Curves.easeIn),
      ),
    );

    _ctrl.forward();

    // Navigate once animation is done
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionDuration: Duration.zero,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: _screenFade.value,
          child: SizedBox.expand(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ── Subtle radial glow behind logo ──────────────────────────
                Opacity(
                  opacity: (_logoOpacity.value * 0.35).clamp(0.0, 1.0),
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x557B3FCC), Colors.transparent],
                      ),
                    ),
                  ),
                ),

                // ── Loading indicator at bottom ─────────────────────────────
                Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: FadeTransition(
                    opacity: _tagOpacity,
                    child: Column(
                      children: [
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              const Color(0xFF7B3FCC).withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Loading...',
                          style: TextStyle(
                            color: Color(0xFF4A5568),
                            fontSize: 12,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Logo + text column ──────────────────────────────────────
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Image.asset(
                          'assets/images/new_logo.png',
                          width: 100,
                          height: 100,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // App name
                    FadeTransition(
                      opacity: _titleOpacity,
                      child: SlideTransition(
                        position: _titleSlide,
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFFB070FF), Color(0xFF00C8FF)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ).createShader(bounds),
                          child: const Text(
                            'Video & Collage Maker',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Tagline
                    FadeTransition(
                      opacity: _tagOpacity,
                      child: const Text(
                        'Create · Edit · Share',
                        style: TextStyle(
                          color: Color(0xFF8A9BB5),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
