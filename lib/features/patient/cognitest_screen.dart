import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:neuroguard/core/services/cognitest_service.dart';
import 'package:neuroguard/core/services/auth_service.dart';
import 'drawing_screen.dart';
import 'package:neuroguard/features/caregiver/cognitest_history_screen.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'package:neuroguard/features/shared/settings_screen.dart';

class CogniTestScreen extends StatefulWidget {
  const CogniTestScreen({super.key});

  @override
  State<CogniTestScreen> createState() => _CogniTestScreenState();
}

class _CogniTestScreenState extends State<CogniTestScreen> {
  final _service = CogniTestService();
  final _authService = AuthService();

  String? _patientId;
  double? _lastTia;
  int? _lastScore;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Use real Firebase Auth UID
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _patientId = uid);

    final sessions = await _service.getPastSessions(uid);
    if (sessions.isNotEmpty) {
      setState(() {
        _lastTia =
            (sessions[0]['avg_time_in_air'] as num?)?.toDouble();
        _lastScore = (sessions[0]['score'] as num?)?.toInt();
      });
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ──────────────────────────────────────
                    const Text(
                      'COGNITEST',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Track your cognitive health',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),

                    const SizedBox(height: 24),

                    // ── Start Test button ────────────────────────────
                    GestureDetector(
                      onTap: _patientId == null
                          ? null
                          : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DrawingScreen(
                            patientId: _patientId!,
                            previousScore: _lastScore,
                            previousTia: _lastTia,),
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            'assets/startbutton.png',
                            width: double.infinity,
                            fit: BoxFit.fitWidth,
                          ),
                          const Text(
                            'START\nTEST',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Hover time pill ──────────────────────────────
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          'assets/hovertime.png',
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24),
                          child: Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'HOVER TIME',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Text(
                                _loading
                                    ? '...'
                                    : _lastTia != null
                                    ? '${_lastTia!.toStringAsFixed(1)}s'
                                    : 'No data',
                                style: const TextStyle(
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

                    // ── Test History pill ────────────────────────────
                    GestureDetector(
                      onTap: _patientId == null
                          ? null
                          : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CogniTestHistoryScreen(
                            callerRole: 'patient',
                            patientId: _patientId!,
                          ),
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            'assets/testhistory.png',
                            width: double.infinity,
                            fit: BoxFit.fitWidth,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24),
                            child: Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'TEST HISTORY',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const Icon(Icons.chevron_right,
                                    color: Colors.black, size: 26),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom Nav ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: PatientBottomNav(
                onSettingsTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}