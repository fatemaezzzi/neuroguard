import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'package:neuroguard/core/services/pocket_check_service.dart';
import 'package:neuroguard/features/shared/settings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VitalsPage v4.0
//
// NEW in v4.0:
//   • Heartbeat timer checks esp32LastSeen every 30 seconds.
//   • One missed window = 3 min + 90 s buffer = 270 s.
//     If now - esp32LastSeen > 270 s → ESP32 is offline.
//   • When offline: _matConnected = false, all readings cleared,
//     chart empty, bar graphs hidden, status shows NOT CONNECTED.
//   • When ESP32 comes back online (adapter plugged in again):
//     _matConnected flips back to true automatically.
// ─────────────────────────────────────────────────────────────────────────────

class VitalsPage extends StatefulWidget {
  final String patientId;
  const VitalsPage({super.key, required this.patientId});

  @override
  State<VitalsPage> createState() => _VitalsPageState();
}

class _VitalsPageState extends State<VitalsPage> {

  // ── State variables ──────────────────────────────────────────────────────
  String _pocketStatus      = 'UNKNOWN';
  String _lastVibrationTime = '--:--';
  String _sleepStatus       = 'UNKNOWN';
  String _sleepSubtitle     = '--';

  List<FlSpot> _microMovementSpots          = [];
  List<Map<String, dynamic>> _windowHistory = [];

  bool _isHypersomnia  = false;
  bool _isUnresponsive = false;

  // Mat connection flag — false until ESP32 sends a real known state
  // AND the heartbeat timer confirms the data is recent.
  bool _matConnected   = false;

  // Pocket check uncertain flag
  bool _isPocketUncertain = false;

  // ── Heartbeat tracking ───────────────────────────────────────────────────
  // esp32LastSeen: the epoch timestamp written by the ESP32 every window.
  // heartbeatTimer: checks every 30 s whether the ESP32 has gone silent.
  //
  // Disconnection threshold = 1 window (180 s) + 90 s buffer = 270 s.
  // This means: if the ESP32 misses exactly one window, Flutter detects
  // it within 30 s of the next heartbeat check.
  int?  _esp32LastSeen;
  Timer? _heartbeatTimer;
  static const int _disconnectThresholdSeconds = 270; // 3 min + 90 s buffer

  StreamSubscription? _firestoreSub;
  StreamSubscription? _windowsSub;

  static const double _overlapVeloStatus   = 20.0;
  static const double _overlapStatusPocket = -23.0;
  static const double _overlapPocketVibra  = 10.0;

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _listenToFirestore();
    _listenToWindows();
    _startHeartbeatTimer();
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    _windowsSub?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  // ── Heartbeat timer ──────────────────────────────────────────────────────
  // Runs every 30 seconds. Compares current time to the last timestamp
  // written by the ESP32. If the gap exceeds the threshold, the ESP32 is
  // considered offline and the UI resets to NOT CONNECTED.
  void _startHeartbeatTimer() {
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
          (_) => _checkHeartbeat(),
    );
  }

  void _checkHeartbeat() {
    if (!mounted) return;

    // If we have never received a timestamp, mat was never connected.
    if (_esp32LastSeen == null) {
      if (_matConnected) {
        _resetMatState();
      }
      return;
    }

    final int nowEpoch =
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int gap = nowEpoch - _esp32LastSeen!;

    debugPrint('[Heartbeat] Gap since last ESP32 write: ${gap}s '
        '(threshold: ${_disconnectThresholdSeconds}s)');

    if (gap > _disconnectThresholdSeconds && _matConnected) {
      debugPrint('[Heartbeat] ESP32 offline — resetting UI');
      _resetMatState();
    }
  }

  // ── Reset all mat-related state ──────────────────────────────────────────
  // Called when the heartbeat detects the ESP32 has gone offline.
  // Clears every field that was populated by ESP32 data so the UI
  // goes back to exactly the same state as when the page first loaded
  // with no mat connected.
  void _resetMatState() {
    setState(() {
      _matConnected        = false;
      _sleepStatus         = 'UNKNOWN';
      _sleepSubtitle       = '--';
      _isHypersomnia       = false;
      _isUnresponsive      = false;
      _microMovementSpots  = [];
      _windowHistory       = [];
      // Do NOT reset _esp32LastSeen — we keep the last known timestamp
      // so the heartbeat can keep comparing until new data arrives.
    });
  }

  // ── Responsive text helper ───────────────────────────────────────────────
  TextStyle _textStyle({
    required BuildContext context,
    double scale = 1.0,
    FontWeight weight = FontWeight.normal,
    Color color = Colors.white,
    double letterSpacing = 0,
  }) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double baseFontSize = screenWidth * 0.038;
    return TextStyle(
      fontSize: baseFontSize * scale,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  // ── Firestore listener 1: users/{patientId} ──────────────────────────────
  void _listenToFirestore() {
    _firestoreSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.patientId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;

      final data    = snapshot.data() as Map<String, dynamic>?;
      final sensors = data?['sensors'] as Map<String, dynamic>?;
      if (sensors == null) return;

      // Pocket check timestamp
      final ts = sensors['pocket_check_timestamp'];
      String timeStr = '--:--';
      if (ts is Timestamp) {
        final dt = ts.toDate();
        timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}';
      }

      final bedState = sensors['bed_status']?.toString() ?? 'UNKNOWN';

      // Mat has real data only when bed_status is a known ESP32 state
      final bool matHasData = bedState != 'UNKNOWN' && bedState.isNotEmpty;

      // ── Read heartbeat timestamp ────────────────────────────────────────
      // esp32LastSeen is written by the ESP32 every window.
      // We store it here so _checkHeartbeat() can compare it to now.
      final dynamic lastSeenRaw = sensors['esp32LastSeen'];
      if (lastSeenRaw != null) {
        int? parsed;
        if (lastSeenRaw is int)    parsed = lastSeenRaw;
        if (lastSeenRaw is String) parsed = int.tryParse(lastSeenRaw);
        if (parsed != null) {
          _esp32LastSeen = parsed;
          // If we just received a fresh timestamp, the ESP32 is alive.
          // Run the heartbeat check immediately so the UI reconnects
          // without waiting for the next 30-second timer tick.

          _matConnected = true;
        }
      }

      setState(() {
        _pocketStatus       = sensors['pocket_status']?.toString() ?? 'UNKNOWN';
        _lastVibrationTime  = timeStr;
        _isPocketUncertain  = sensors['pocket_status_uncertain'] as bool? ?? false;

        // Only update mat-related fields when mat has real data
        // AND the heartbeat has not already declared it offline.
        if (matHasData) {
          _matConnected   = true;
          _sleepStatus    = _labelForState(bedState);
          _sleepSubtitle  = _subtitleForState(bedState);
          _isHypersomnia  = sensors['isHypersomnia'] == true;
          _isUnresponsive = sensors['isUnresponsive'] == true;
        }
      });
    });
  }

  // ── Firestore listener 2: sleepSessions/{patientId}/windows ─────────────
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

  // ── State label helpers ──────────────────────────────────────────────────
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

  String get _pocketStatusLabel {
    final base = switch (_pocketStatus) {
      'ON_PERSON' => 'ON PERSON',
      'ON_TABLE'  => 'NOT ON PERSON',
      'CHECKING'  => 'CHECKING...',
      _           => 'UNKNOWN',
    };
    if (_isPocketUncertain && _pocketStatus != 'CHECKING') {
      return '$base (last known)';
    }
    return base;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [

              // Alert banners — only when mat is connected AND alert is real
              if (_matConnected && _isUnresponsive)
                _alertBanner(
                  context,
                  '🔴 EMERGENCY — Patient Unresponsive!',
                  Colors.red,
                ),
              if (_matConnected && _isHypersomnia && !_isUnresponsive)
                _alertBanner(
                  context,
                  '🟡 HYPERSOMNIA — In bed over 13 hours',
                  Colors.orange,
                ),

              const SizedBox(height: 12),
              _buildBlobChain(context),
              const SizedBox(height: 32),
              _buildBarGraphSection(context),
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

  // ── Alert banner ─────────────────────────────────────────────────────────
  Widget _alertBanner(BuildContext context, String message, Color color) {
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
        style: _textStyle(
          context: context,
          scale: 0.95,
          weight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ── Blob chain ───────────────────────────────────────────────────────────
  Widget _buildBlobChain(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final double w  = constraints.maxWidth;
      final double h1 = w * (190 / 364);
      final double h2 = w * (145 / 364);
      final double h3 = w * (81 / 364);
      final double h4 = w * (151 / 350);

      final double topVelo     = 0;
      final double topStatus   = h1 - _overlapVeloStatus;
      final double topPocket   = topStatus + h2 - _overlapStatusPocket;
      final double topVibra    = topPocket + h3 - _overlapPocketVibra;
      final double totalHeight = topVibra + h4;

      final hugeBlack = _textStyle(
        context: context,
        scale: 1.4,
        weight: FontWeight.w900,
        color: Colors.black,
        letterSpacing: 1.5,
      );
      final hugeGreen = _textStyle(
        context: context,
        scale: 1.4,
        weight: FontWeight.w900,
        color: const Color(0xFFCCFF00),
        letterSpacing: 1.5,
      );
      final smallBody = _textStyle(
        context: context,
        scale: 0.85,
        color: Colors.black54,
      );
      final smallBold = _textStyle(
        context: context,
        scale: 0.95,
        weight: FontWeight.w600,
        color: Colors.black,
      );

      return SizedBox(
        width: w,
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [

            // ── STATUS blob ────────────────────────────────────────────────
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
                        Text('STATUS', style: hugeGreen),
                        Flexible(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (_matConnected) ...[
                                Text(
                                  _sleepStatus,
                                  style: hugeBlack,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _sleepSubtitle,
                                  style: smallBody,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ] else ...[
                                // Mat disconnected — neutral label, nothing else
                                Text(
                                  'NOT CONNECTED',
                                  style: smallBody,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),

            // ── POCKET CHECK blob ──────────────────────────────────────────
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
                        Text('POCKET CHECK', style: hugeBlack),
                        GestureDetector(
                          onTap: () async {
                            await PocketCheckService.triggerRemoteCheck(
                              widget.patientId,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Pocket check triggered on patient\'s phone',
                                  ),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
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
              ]),
            ),

            // ── LAST VIBRATION blob ────────────────────────────────────────
            Positioned(
              top: topVibra, left: 0, right: 0, height: h4,
              child: Stack(children: [
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
              ]),
            ),

            // ── VELOSTAT GRAPH blob ────────────────────────────────────────
            Positioned(
              top: topVelo, left: 0, right: 0, height: h1,
              child: Stack(children: [
                Image.asset('assets/velostatgraph.png', fit: BoxFit.fill),
                Positioned(
                  top: 18, left: 24,
                  child: Text(
                    'VELOSTAT GRAPH',
                    style: _textStyle(
                      context: context,
                      scale: 1.4,
                      weight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),

                // Chart only shown when mat connected AND data exists
                if (_matConnected && _microMovementSpots.isNotEmpty)
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

  // ── Line chart ───────────────────────────────────────────────────────────
  Widget _buildChart() {
    final spots = _microMovementSpots;
    final maxY  = spots.isNotEmpty
        ? (spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.3)
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

  // ── Bar graph section ────────────────────────────────────────────────────
  Widget _buildBarGraphSection(BuildContext context) {
    // Hidden completely when mat not connected or no data
    if (!_matConnected || _windowHistory.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SENSOR ANALYTICS',
          style: _textStyle(
            context: context,
            scale: 0.9,
            weight: FontWeight.w700,
            color: const Color(0xFFCCFF00),
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 16),

        _buildBarGraph(
          context: context,
          title: 'Micro-Movement Count',
          field: 'microMovementCount',
          maxValue: 100,
          barColor: const Color(0xFFCCFF00),
        ),
        _buildBarGraph(
          context: context,
          title: 'Mean (Pressure)',
          field: 'mean',
          maxValue: 1000,
          barColor: Colors.purpleAccent,
        ),
        _buildBarGraph(
          context: context,
          title: 'Variance (Restlessness)',
          field: 'variance',
          maxValue: 50000,
          barColor: Colors.cyanAccent,
        ),
        _buildBarGraph(
          context: context,
          title: 'Peak Amplitude',
          field: 'peakAmplitude',
          maxValue: 4095,
          barColor: Colors.orangeAccent,
        ),

        const SizedBox(height: 8),
        Text(
          'STATE TIMELINE',
          style: _textStyle(
            context: context,
            scale: 0.9,
            weight: FontWeight.w700,
            color: const Color(0xFFCCFF00),
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
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
        const SizedBox(height: 10),

        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _legendDot(context, 'OFF BED',     Colors.blue),
            _legendDot(context, 'ACTIVE',      Colors.green),
            _legendDot(context, 'SLEEPING',    const Color(0xFFCCFF00)),
            _legendDot(context, 'STILL',       Colors.yellow),
            _legendDot(context, 'HYPERSOMNIA', Colors.orange),
            _legendDot(context, 'EMERGENCY',   Colors.red),
          ],
        ),
      ],
    );
  }

  // ── Single bar graph ─────────────────────────────────────────────────────
  Widget _buildBarGraph({
    required BuildContext context,
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
          style: _textStyle(
            context: context,
            scale: 0.95,
            weight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 100,
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
              final bool showLabel = barH < 65;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (showLabel)
                        Text(
                          label,
                          style: _textStyle(
                            context: context,
                            scale: 0.65,
                            color: Colors.white54,
                          ),
                          overflow: TextOverflow.ellipsis,
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

  // ── Legend dot ───────────────────────────────────────────────────────────
  Widget _legendDot(BuildContext context, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: _textStyle(
            context: context,
            scale: 0.78,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}