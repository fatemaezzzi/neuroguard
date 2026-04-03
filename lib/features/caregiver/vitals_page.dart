import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'package:neuroguard/core/services/pocket_check_service.dart';
import 'package:neuroguard/features/shared/settings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VitalsPage — CAREGIVER side
//
// KEY FIX: PocketCheckService.initialize() has been removed from this file.
// The service (vibration + accelerometer + Firestore listener) must only ever
// run on the PATIENT device, via PocketCheckInitializer in patient_home.dart.
//
// What this page is allowed to do:
//   • READ from Firestore (sensors node) — ✅ via _listenToFirestore()
//   • WRITE the trigger flag to Firestore — ✅ via PocketCheckService.triggerRemoteCheck()
//     (static helper — no service instance needed)
//
// What this page must NOT do:
//   • Instantiate PocketCheckService — ❌ removed
//   • Call _pocketService.initialize() — ❌ removed
// ─────────────────────────────────────────────────────────────────────────────
class VitalsPage extends StatefulWidget {
  /// The real patient UID — must be passed in from the caregiver's navigation.
  /// Previously hardcoded to 'patient_01' which meant every caregiver always
  /// monitored the same test account.
  final String patientId;

  const VitalsPage({super.key, required this.patientId});

  @override
  State<VitalsPage> createState() => _VitalsPageState();
}

class _VitalsPageState extends State<VitalsPage> {
  String _pocketStatus = 'UNKNOWN';
  String _lastVibrationTime = '--:--';
  String _sleepStatus = 'SLEEPING';
  String _sleepSubtitle = 'low movement, on bed';

  // No PocketCheckService instance here — caregiver side never owns one.
  StreamSubscription? _firestoreSub;

  @override
  void initState() {
    super.initState();
    // Only start the Firestore READ listener — no service initialization.
    _listenToFirestore();
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    super.dispose();
  }

  // ── Firestore READ listener (caregiver reads patient's sensor results) ─────
  void _listenToFirestore() {
    _firestoreSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.patientId)   // uses the real patient ID passed in
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;

      final data = snapshot.data() as Map<String, dynamic>?;
      final sensors = data?['sensors'] as Map<String, dynamic>?;

      if (sensors != null) {
        final ts = sensors['pocket_check_timestamp'];

        String timeStr = '--:--';
        if (ts is Timestamp) {
          final dt = ts.toDate();
          timeStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }

        setState(() {
          _pocketStatus = sensors['pocket_status']?.toString() ?? 'UNKNOWN';
          _lastVibrationTime = timeStr;
        });
      }
    });
  }

  String get _pocketStatusLabel => switch (_pocketStatus) {
    'ON_PERSON' => 'ON PERSON',
    'ON_TABLE'  => 'NOT ON PERSON',
    'CHECKING'  => 'CHECKING...',
    _           => 'UNKNOWN',
  };

  static const TextStyle _hugeBlack = TextStyle(
    fontWeight: FontWeight.w900,
    fontSize: 22,
    letterSpacing: 1.5,
    color: Colors.black,
  );

  static const TextStyle _hugeGreen = TextStyle(
    fontWeight: FontWeight.w900,
    fontSize: 22,
    letterSpacing: 1.5,
    color: Color(0xFFCCFF00),
  );

  static const TextStyle _smallBody = TextStyle(
    fontSize: 12,
    color: Colors.black54,
  );

  static const TextStyle _smallBold = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.black,
  );

  static const double _overlapVeloStatus   = 20.0;
  static const double _overlapStatusPocket = -23.0;
  static const double _overlapPocketVibra  = 10.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              _buildBlobChain(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CaregiverBottomNav(
        onSettingsTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
    );
  }

  Widget _buildBlobChain() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;

        final double h1 = w * (190 / 364);
        final double h2 = w * (145 / 364);
        final double h3 = w * (81 / 364);
        final double h4 = w * (151 / 350);

        final double topVelo   = 0;
        final double topStatus = h1 - _overlapVeloStatus;
        final double topPocket = topStatus + h2 - _overlapStatusPocket;
        final double topVibra  = topPocket + h3 - _overlapPocketVibra;
        final double totalHeight = topVibra + h4;

        return SizedBox(
          width: w,
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [

              /// STATUS
              Positioned(
                top: topStatus,
                left: 0,
                right: 0,
                height: h2,
                child: Stack(
                  children: [
                    Image.asset('assets/statussleeping.png', fit: BoxFit.fill),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('STATUS', style: _hugeGreen),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_sleepStatus, style: _hugeBlack),
                                const SizedBox(height: 2),
                                Text(_sleepSubtitle, style: _smallBody),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              /// POCKET CHECK — button only writes Firestore trigger flag.
              /// No PocketCheckService instance needed here.
              Positioned(
                top: topPocket,
                left: 0,
                right: 0,
                height: h3,
                child: Stack(
                  children: [
                    Image.asset('assets/pocketcheck.png', fit: BoxFit.fill),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('POCKET CHECK', style: _hugeBlack),
                            GestureDetector(
                              onTap: () async {
                                // triggerRemoteCheck is a static method — it
                                // only writes commands.trigger_pocket_check=true
                                // to Firestore. The patient's PocketCheckService
                                // (running in PocketCheckInitializer) picks this
                                // up, vibrates, runs the algorithm, and writes
                                // the result back. Nothing runs on this device.
                                await PocketCheckService.triggerRemoteCheck(
                                  widget.patientId,
                                );
                              },
                              child: Image.asset(
                                'assets/arrow.png',
                                width: 30,
                                height: 30,
                                color: const Color(0xFFCCFF00),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              /// LAST VIBRATION
              Positioned(
                top: topVibra,
                left: 0,
                right: 0,
                height: h4,
                child: Stack(
                  children: [
                    Image.asset('assets/lastvibrationtest.png',
                        fit: BoxFit.fill),
                    Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('LAST VIBRATION TEST', style: _hugeBlack),
                          const SizedBox(height: 4),
                          Text(_lastVibrationTime, style: _smallBold),
                          const SizedBox(height: 2),
                          Text(_pocketStatusLabel, style: _hugeBlack),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              /// GRAPH
              Positioned(
                top: topVelo,
                left: 0,
                right: 0,
                height: h1,
                child: Stack(
                  children: [
                    Image.asset('assets/velostatgraph.png', fit: BoxFit.fill),
                    const Positioned(
                      top: 18,
                      left: 24,
                      child: Text('VELOSTAT GRAPH', style: _hugeBlack),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      top: h1 * 0.38,
                      bottom: 16,
                      child: _buildChart(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChart() {
    final spots = [
      const FlSpot(0, 1.2),
      const FlSpot(1, 1.8),
      const FlSpot(2, 1.5),
      const FlSpot(3, 2.1),
      const FlSpot(4, 1.9),
      const FlSpot(5, 1.6),
      const FlSpot(6, 2.3),
      const FlSpot(7, 2.0),
      const FlSpot(8, 1.7),
      const FlSpot(9, 2.2),
    ];

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: 9,
        minY: 0,
        maxY: 3,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.black.withValues(alpha: 0.7),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.black.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}