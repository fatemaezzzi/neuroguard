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

  StreamSubscription? _firestoreSub;

  @override
  void initState() {
    super.initState();
    _listenToFirestore();
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    super.dispose();
  }

  void _listenToFirestore() {
    _firestoreSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.patientId)
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

  // ── Overlap constants — positive = blobs overlap each other (chain effect)
  // _overlapStatusPocket was -23 which created a GAP, not an overlap.
  // Image 1 shows the pocket blob should tuck INTO the status blob slightly.
  static const double _overlapVeloStatus   = 20.0;
  static const double _overlapStatusPocket = 14.0;  // FIX: was -23 (gap) → 14 (overlap)
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

        // Heights computed from original asset aspect ratios
        final double h1 = w * (190 / 364);
        final double h2 = w * (145 / 364);
        final double h3 = w * (81 / 364);
        final double h4 = w * (151 / 350);

        // Scale font sizes proportionally to blob width so text never overflows
        // Base design was ~364px wide → derive a scale factor from actual width
        final double fontScale = (w / 364).clamp(0.7, 1.3);
        final double hugeFontSize  = 22 * fontScale;
        final double smallFontSize = 12 * fontScale;
        final double boldFontSize  = 14 * fontScale;

        final TextStyle hugeBlack = TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: hugeFontSize,
          letterSpacing: 1.2,
          color: Colors.black,
        );
        final TextStyle hugeGreen = TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: hugeFontSize,
          letterSpacing: 1.2,
          color: const Color(0xFFCCFF00),
        );
        final TextStyle smallBody = TextStyle(
          fontSize: smallFontSize,
          color: Colors.black54,
        );
        final TextStyle smallBold = TextStyle(
          fontSize: boldFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        );

        final double topVelo   = 0;
        final double topStatus = h1 - _overlapVeloStatus;
        final double topPocket = topStatus + h2 - _overlapStatusPocket; // FIX: now subtracts correctly
        final double topVibra  = topPocket + h3 - _overlapPocketVibra;
        final double totalHeight = topVibra + h4;

        return SizedBox(
          width: w,
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [

              /// GRAPH — rendered first (bottom of Z-order) so STATUS overlaps it
              Positioned(
                top: topVelo,
                left: 0,
                right: 0,
                height: h1,
                child: Stack(
                  children: [
                    Image.asset('assets/velostatgraph.png', fit: BoxFit.fill),
                    Positioned(
                      top: 18,
                      left: 24,
                      child: Text('VELOSTAT GRAPH', style: hugeBlack),
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
                        // FIX: reduced horizontal padding so text has more room
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // FIX: wrap left label so it doesn't push right side off screen
                            Text('STATUS', style: hugeGreen),
                            // FIX: Flexible + textAlign prevents overflow on small screens
                            Flexible(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _sleepStatus,
                                    style: hugeBlack,
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _sleepSubtitle,
                                    style: smallBody,
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              /// POCKET CHECK
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
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('POCKET CHECK', style: hugeBlack),
                            GestureDetector(
                              onTap: () async {
                                await PocketCheckService.triggerRemoteCheck(
                                  widget.patientId,
                                );
                              },
                              // FIX: slightly larger tap target, vertically centered
                              child: Image.asset(
                                'assets/arrow.png',
                                width: 32,
                                height: 32,
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

              /// LAST VIBRATION TEST
              Positioned(
                top: topVibra,
                left: 0,
                right: 0,
                height: h4,
                child: Stack(
                  children: [
                    Image.asset('assets/lastvibrationtest.png', fit: BoxFit.fill),
                    Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('LAST VIBRATION TEST', style: hugeBlack),
                          const SizedBox(height: 4),
                          Text(_lastVibrationTime, style: smallBold),
                          const SizedBox(height: 2),
                          Text(_pocketStatusLabel, style: hugeBlack),
                        ],
                      ),
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