import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'package:neuroguard/core/services/pocket_check_service.dart';
import 'package:neuroguard/features/shared/settings_screen.dart';

class VitalsPage extends StatefulWidget {
  final String patientId;
  const VitalsPage({super.key, required this.patientId});

  @override
  State<VitalsPage> createState() => _VitalsPageState();
}

class _VitalsPageState extends State<VitalsPage> {

  String _pocketStatus      = 'UNKNOWN';
  String _lastVibrationTime = '--:--';
  String _sleepStatus       = 'UNKNOWN';
  String _sleepSubtitle     = '--';

  List<FlSpot> _microMovementSpots = [];
  List<Map<String, dynamic>> _windowHistory = [];

  bool _isHypersomnia  = false;
  bool _isUnresponsive = false;

  StreamSubscription? _firestoreSub;
  StreamSubscription? _windowsSub;

  static const TextStyle _hugeBlack = TextStyle(
    fontWeight: FontWeight.w900, fontSize: 22,
    letterSpacing: 1.5, color: Colors.black,
  );
  static const TextStyle _hugeGreen = TextStyle(
    fontWeight: FontWeight.w900, fontSize: 22,
    letterSpacing: 1.5, color: Color(0xFFCCFF00),
  );
  static const TextStyle _smallBody = TextStyle(
    fontSize: 12, color: Colors.black54,
  );
  static const TextStyle _smallBold = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black,
  );

  static const double _overlapVeloStatus   = 20.0;
  static const double _overlapStatusPocket = -23.0;
  static const double _overlapPocketVibra  = 10.0;

  @override
  void initState() {
    super.initState();
    _listenToFirestore();
    _listenToWindows();
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    _windowsSub?.cancel();
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

      debugPrint('=== FIRESTORE DATA ===');
      debugPrint(data.toString());
      debugPrint('=== SENSORS NODE ===');
      debugPrint(data?['sensors'].toString());

      final sensors = data?['sensors'] as Map<String, dynamic>?;
      if (sensors == null) return;

      debugPrint('=== BED STATUS ===');
      debugPrint(sensors['bed_status']?.toString() ?? 'null');

      final ts = sensors['pocket_check_timestamp'];
      String timeStr = '--:--';
      if (ts is Timestamp) {
        final dt = ts.toDate();
        timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}';
      }

      final bedState = sensors['bed_status']?.toString() ?? 'UNKNOWN';

      setState(() {
        _pocketStatus      = sensors['pocket_status']?.toString() ?? 'UNKNOWN';
        _lastVibrationTime = timeStr;
        _sleepStatus       = _labelForState(bedState);
        _sleepSubtitle     = _subtitleForState(bedState);
        _isHypersomnia     = sensors['isHypersomnia'] == true;
        _isUnresponsive    = sensors['isUnresponsive'] == true;
      });
    });
  }

  void _listenToWindows() {
    _windowsSub = FirebaseFirestore.instance
        .collection('sleepSessions')
        .doc(widget.patientId)
        .collection('windows')
        .orderBy('epochTimestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;

      final windows = snap.docs
          .map((d) => d.data())
          .toList()
          .reversed
          .toList();

      final spots = <FlSpot>[];
      for (int i = 0; i < windows.length; i++) {
        final val = windows[i]['microMovementCount'];
        double y = 0;
        if (val is int)    y = val.toDouble();
        if (val is double) y = val;
        spots.add(FlSpot(i.toDouble(), y));
      }

      setState(() {
        _microMovementSpots = spots;
        _windowHistory      = windows;
      });
    });
  }

  String _labelForState(String state) => switch (state) {
    'OFF_BED'       => 'OFF BED',
    'ON_BED_STILL'  => 'STILL',
    'ON_BED_LIGHT'  => 'SLEEPING',
    'ON_BED_ACTIVE' => 'ACTIVE',
    'HYPERSOMNIA'   => 'HYPERSOMNIA',
    'UNRESPONSIVE'  => 'EMERGENCY',
    _               => 'UNKNOWN',
  };

  String _subtitleForState(String state) => switch (state) {
    'OFF_BED'       => 'patient not on bed',
    'ON_BED_STILL'  => 'no movement detected',
    'ON_BED_LIGHT'  => 'low movement, on bed',
    'ON_BED_ACTIVE' => 'active movement detected',
    'HYPERSOMNIA'   => 'in bed over 13 hours',
    'UNRESPONSIVE'  => 'no movement — check patient!',
    _               => '--',
  };

  Color _stateColor(String state) => switch (state) {
    'UNRESPONSIVE'  => Colors.red,
    'HYPERSOMNIA'   => Colors.orange,
    'ON_BED_STILL'  => Colors.yellow,
    'ON_BED_LIGHT'  => const Color(0xFFCCFF00),
    'ON_BED_ACTIVE' => Colors.green,
    'OFF_BED'       => Colors.blue,
    _               => Colors.grey,
  };

  String get _pocketStatusLabel => switch (_pocketStatus) {
    'ON_PERSON' => 'ON PERSON',
    'ON_TABLE'  => 'NOT ON PERSON',
    'CHECKING'  => 'CHECKING...',
    _           => 'UNKNOWN',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              if (_isUnresponsive)
                _alertBanner('🔴 EMERGENCY — Patient Unresponsive!', Colors.red),
              if (_isHypersomnia && !_isUnresponsive)
                _alertBanner('🟡 HYPERSOMNIA — In bed over 13 hours', Colors.orange),

              const SizedBox(height: 12),
              _buildBlobChain(),
              const SizedBox(height: 32),
              _buildBarGraphSection(),
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

  Widget _alertBanner(String message, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: color, fontSize: 13, fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBlobChain() {
    return LayoutBuilder(builder: (context, constraints) {
      final double w = constraints.maxWidth;
      final double h1 = w * (190 / 364);
      final double h2 = w * (145 / 364);
      final double h3 = w * (81 / 364);
      final double h4 = w * (151 / 350);

      final double topVelo     = 0;
      final double topStatus   = h1 - _overlapVeloStatus;
      final double topPocket   = topStatus + h2 - _overlapStatusPocket;
      final double topVibra    = topPocket + h3 - _overlapPocketVibra;
      final double totalHeight = topVibra + h4;

      return SizedBox(
        width: w,
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [

            // STATUS
            Positioned(
              top: topStatus, left: 0, right: 0, height: h2,
              child: Stack(children: [
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
              ]),
            ),

            // POCKET CHECK
            Positioned(
              top: topPocket, left: 0, right: 0, height: h3,
              child: Stack(children: [
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
                            await PocketCheckService.triggerRemoteCheck(
                              widget.patientId,
                            );
                          },
                          child: Image.asset(
                            'assets/arrow.png',
                            width: 30, height: 30,
                            color: const Color(0xFFCCFF00),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),

            // LAST VIBRATION
            Positioned(
              top: topVibra, left: 0, right: 0, height: h4,
              child: Stack(children: [
                Image.asset('assets/lastvibrationtest.png', fit: BoxFit.fill),
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
              ]),
            ),

            // VELOSTAT GRAPH
            Positioned(
              top: topVelo, left: 0, right: 0, height: h1,
              child: Stack(children: [
                Image.asset('assets/velostatgraph.png', fit: BoxFit.fill),
                const Positioned(
                  top: 18, left: 24,
                  child: Text('VELOSTAT GRAPH', style: _hugeBlack),
                ),
                Positioned(
                  left: 16, right: 16,
                  top: h1 * 0.38, bottom: 16,
                  child: _buildChart(),
                ),
              ]),
            ),

          ],
        ),
      );
    });
  }

  Widget _buildChart() {
    final spots = _microMovementSpots.isNotEmpty
        ? _microMovementSpots
        : List.generate(10, (i) => FlSpot(i.toDouble(), 0));

    final maxY = _microMovementSpots.isNotEmpty
        ? (_microMovementSpots
        .map((s) => s.y)
        .reduce((a, b) => a > b ? a : b) *
        1.3)
        .clamp(10.0, 200.0)
        : 50.0;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (spots.length - 1).toDouble().clamp(1, 9),
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.black.withOpacity(0.7),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.black.withOpacity(0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarGraphSection() {
    if (_windowHistory.isEmpty) {
      return const Center(
        child: Text(
          'Waiting for sensor data...',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SENSOR ANALYTICS',
          style: TextStyle(
            color: Color(0xFFCCFF00), fontSize: 12,
            fontWeight: FontWeight.w700, letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 16),

        _buildBarGraph(
          title: 'Micro-Movement Count',
          field: 'microMovementCount',
          maxValue: 100,
          barColor: const Color(0xFFCCFF00),
        ),
        _buildBarGraph(
          title: 'Mean (Pressure)',
          field: 'mean',
          maxValue: 1000,
          barColor: Colors.purpleAccent,
        ),
        _buildBarGraph(
          title: 'Variance (Restlessness)',
          field: 'variance',
          maxValue: 50000,
          barColor: Colors.cyanAccent,
        ),
        _buildBarGraph(
          title: 'Peak Amplitude',
          field: 'peakAmplitude',
          maxValue: 4095,
          barColor: Colors.orangeAccent,
        ),

        const SizedBox(height: 8),
        const Text(
          'STATE TIMELINE',
          style: TextStyle(
            color: Color(0xFFCCFF00), fontSize: 12,
            fontWeight: FontWeight.w700, letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: Row(
            children: _windowHistory.map((w) {
              final state = w['state']?.toString() ?? 'UNKNOWN';
              return Expanded(
                child: Tooltip(
                  message: state,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: _stateColor(state),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),

        Wrap(
          spacing: 12, runSpacing: 6,
          children: [
            _legendDot('OFF BED',     Colors.blue),
            _legendDot('ACTIVE',      Colors.green),
            _legendDot('SLEEPING',    const Color(0xFFCCFF00)),
            _legendDot('STILL',       Colors.yellow),
            _legendDot('HYPERSOMNIA', Colors.orange),
            _legendDot('EMERGENCY',   Colors.red),
          ],
        ),
      ],
    );
  }

  Widget _buildBarGraph({
    required String title,
    required String field,
    required double maxValue,
    required Color barColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 90,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _windowHistory.map((w) {
              double raw = 0;
              final val = w[field];
              if (val is int)    raw = val.toDouble();
              if (val is double) raw = val;

              final barH  = (raw / maxValue * 80).clamp(2.0, 80.0);
              final label = raw >= 1000
                  ? '${(raw / 1000).toStringAsFixed(1)}k'
                  : raw.toStringAsFixed(0);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white38, fontSize: 8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: barH,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 9),
        ),
      ],
    );
  }
}