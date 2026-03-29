import 'package:flutter/material.dart';
import 'package:neuroguard/features/caregiver/cognitest_history_screen.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'drawing_screen.dart';
import 'package:neuroguard/features/shared/settings_screen.dart';

class CogniTestScreen extends StatelessWidget {
  const CogniTestScreen({super.key});

  // TODO: replace with real patient ID from Firebase Auth when ready
  static const String _patientId = 'patient_01';

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

              // ── Main Card ───────────────────────────────────────────
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/fixtheclock.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Image.asset(
                            'assets/FIX THE CLOCK.png',
                            height: 36,
                          ),
                        ),
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

                        // ── START TEST wired to DrawingScreen ──────────
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: 28, left: 24, right: 24),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const DrawingScreen(
                                    patientId: _patientId,
                                  ),
                                ),
                              );
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

              // ── Hover Time pill ──────────────────────────────────────
              Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    'assets/hovertime.png',
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                  ),
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
                          '2.3s', // TODO: load from last Firebase session
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

              // ── Test History pill ────────────────────────────────────
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
                    Image.asset(
                      'assets/testhistory.png',
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                    ),
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
                          Icon(Icons.chevron_right, color: Colors.black, size: 26),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Bottom Nav ───────────────────────────────────────────
          PatientBottomNav(
            onSettingsTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),

            const SizedBox(height: 8),
        ],
        ),
      ),
    ),
    );
  }
}