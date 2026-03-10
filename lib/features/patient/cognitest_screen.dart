import 'package:flutter/material.dart';
import 'package:neuroguard/features/caregiver/cognitest_history_screen.dart';

class CogniTestScreen extends StatelessWidget {
  const CogniTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Header ──────────────────────────────────────────────
              const Text(
                'COGNITEST',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),

              const SizedBox(height: 20),

              // ── Main Card using fixtheclock.png as background ────────
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [

                    // The lime green card background
                    Positioned.fill(
                      child: Image.asset(
                        'assets/fixtheclock.png',
                        fit: BoxFit.fill,
                      ),
                    ),

                    // Content on top of card
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [

                        // "FIX THE CLOCK" title asset
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Image.asset(
                            'assets/FIX THE CLOCK.png',
                            height: 36,
                          ),
                        ),

                        // Clock circle asset
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 36,
                                vertical: 16,
                              ),
                              child: Image.asset(
                                'assets/clock.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),

                        // START TEST button asset
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: 28, left: 24, right: 24),
                          child: GestureDetector(
                            onTap: () {
                              // TODO: Navigate to drawing screen when feature is ready
                            },
                            child: Image.asset(
                              'assets/startbutton.png',
                              width: double.infinity,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Hover Time pill asset ────────────────────────────────
              Stack(
                alignment: Alignment.center,
                children: [
                  // Pill background
                  Image.asset(
                    'assets/hovertime.png',
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                  ),
                  // Text overlay on top of the asset
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'HOVER TIME',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          '2.3s',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Test History pill asset ──────────────────────────────
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CogniTestHistoryScreen(),
                    ),
                  );
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pill background
                    Image.asset(
                      'assets/testhistory.png',
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                    ),
                    // Text overlay
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text(
                            'TEST HISTORY',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.black,
                            size: 26,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Bottom Nav Bar ───────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _NavButton(
                    assetPath: 'assets/glassbubble.png',
                    onTap: () => Navigator.pop(context),
                  ),
                  _NavButton(
                    assetPath: 'assets/settingsblob.png',
                    onTap: () {},
                  ),
                ],
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom Nav Circle Button ───────────────────────────────────────────────────
class _NavButton extends StatelessWidget {
  final String assetPath;
  final VoidCallback onTap;
  const _NavButton({required this.assetPath, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Image.asset(
        assetPath,
        width: 62,
        height: 62,
      ),
    );
  }
}