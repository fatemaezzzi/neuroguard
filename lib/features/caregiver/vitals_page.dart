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

  // ── State variables ──────────────────────────────────────────────────────
  String _pocketStatus      = 'UNKNOWN';
  String _lastVibrationTime = '--:--';
  String _sleepStatus       = 'UNKNOWN';
  String _sleepSubtitle     = '--';

  List<FlSpot> _microMovementSpots          = [];
  List<Map<String, dynamic>> _windowHistory = [];

  bool _isHypersomnia = false;
  bool _isUnresponsive = false;

  // FIX 1 — Mat connection flag.
  // Stays false until the ESP32 sends a real known bed_status value.
  // All sensor-mat UI elements are hidden while this is false.
  bool _matConnected = false;

  // FIX 4 — Track pocket_status_uncertain so the vitals blob shows
  // "(last known)" just like PocketCheckCard does. Without this field
  // the blob silently displayed a stale status with no caveat.
  bool _isPocketUncertain = false;

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
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    _windowsSub?.cancel();
    super.dispose();
  }

  // ── Responsive text helper ───────────────────────────────────────────────
  // Scales font size proportionally to screen width so nothing overflows
  // on small phones and text is not tiny on large ones.
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

  // ── Firestore listener 1: users/{patientId} (live status + pocket check) ─
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

      // Pocket check timestamp (unchanged)
      final ts = sensors['pocket_check_timestamp'];
      String timeStr = '--:--';
      if (ts is Timestamp) {
        final dt = ts.toDate();
        timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}';
      }

      final bedState = sensors['bed_status']?.toString() ?? 'UNKNOWN';

      // FIX 2 — Mat is only considered connected when bed_status is a real
      // known state written by the ESP32. 'UNKNOWN' or empty means the ESP32
      // has never written to this field — mat is not connected.
      final bool matHasData = bedState != 'UNKNOWN' && bedState.isNotEmpty;

      setState(() {
        _pocketStatus      = sensors['pocket_status']?.toString() ?? 'UNKNOWN';
        _lastVibrationTime = timeStr;
        _matConnected      = matHasData;

        // FIX 4 — Read pocket_status_uncertain so _pocketStatusLabel can
        // append "(last known)" when the service fell back to prior status.
        _isPocketUncertain = sensors['pocket_status_uncertain'] as bool? ?? false;

        // FIX 2 continued — only update sleep display when mat is connected.
        // If mat is not connected these values stay at their initial defaults
        // but they won't be shown in the UI anyway.
        if (matHasData) {
          _sleepStatus    = _labelForState(bedState);
          _sleepSubtitle  = _subtitleForState(bedState);
          _isHypersomnia  = sensors['isHypersomnia'] == true;
          _isUnresponsive = sensors['isUnresponsive'] == true;
        }
      });
    });
  }

  // ── Firestore listener 2: sleepSessions/{patientId}/windows ─────────────
  // Feeds the line chart and bar graphs.
  // _matConnected gates display of these — data may arrive but won't show
  // until the live status confirms the mat is connected.
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

  // FIX 4 — _pocketStatusLabel now appends "(last known)" when the service
  // fell back to a prior definitive status after an ambiguous vote.
  // Previously this field was ignored here even though PocketCheckCard
  // already handled it correctly.
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

              // FIX 5 — Alert banners only show when mat is connected AND
              // the alert flag is actually true. Never shown when mat is off.
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

                              // FIX 3 — Status text only shown when mat is
                              // connected. When not connected shows a small
                              // neutral label so the blob is not empty but
                              // no misleading state is displayed.
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
            // Pocket check is independent of mat — always shown.
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
                            // Write the trigger flag to the PATIENT's Firestore doc.
                            // The PocketCheckService running on the patient's phone
                            // watches this flag and runs the vibrate + accelerometer
                            // check entirely on the patient device.
                            // Nothing sensor-related should run here on the caregiver phone.
                            await PocketCheckService.triggerRemoteCheck(widget.patientId);

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Pocket check triggered on patient\'s phone'),
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
            // Last vibration is independent of mat — always shown.
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
                      // FIX 4 — _pocketStatusLabel now includes "(last known)"
                      // when _isPocketUncertain is true, matching PocketCheckCard.
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

                // FIX 4 — Line chart only rendered when mat is connected AND
                // at least one real window of data has arrived.
                // When mat is not connected the graph area is completely empty
                // — no flat zero line, no dummy data, nothing.
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

  // ── Line chart — real micro-movement data ────────────────────────────────
  Widget _buildChart() {
    final spots = _microMovementSpots;

    final maxY = spots.isNotEmpty
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
    // FIX 6 — When mat is not connected OR no window data has arrived yet,
    // return an empty SizedBox — no text, no placeholder, nothing at all.
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

              // Only show value label when bar is short enough to have room
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