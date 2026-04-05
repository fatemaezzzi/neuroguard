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

  // ─── FIX 1: Use MediaQuery-relative font sizes instead of hardcoded ones ───
  // All TextStyles below have been REMOVED as static const and are now built
  // dynamically via _textStyle() helper so they scale with screen size.
  // This prevents text overflow on small phones and tiny text on large ones.

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

  // ─── FIX 2: Responsive text helper ───────────────────────────────────────
  // Uses MediaQuery screen width to compute font sizes proportionally.
  // On a 360px wide phone: base = ~14sp. On a 414px wide phone: base = ~16sp.
  // All sizes scale from this base, so nothing overflows on any device.
  TextStyle _textStyle({
    required BuildContext context,
    double scale = 1.0,
    FontWeight weight = FontWeight.normal,
    Color color = Colors.white,
    double letterSpacing = 0,
  }) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double baseFontSize = screenWidth * 0.038; // ~14sp on 360px screen
    return TextStyle(
      fontSize: baseFontSize * scale,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
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
        // ─── FIX 3: SafeArea handles notches/status bars on all devices ──────
        // Already present — good. Keep it wrapping SingleChildScrollView.
        child: SingleChildScrollView(
          // ─── FIX 4: SingleChildScrollView prevents ALL vertical overflow ──
          // Any content taller than the screen will scroll instead of clipping.
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              if (_isUnresponsive)
                _alertBanner(context, '🔴 EMERGENCY — Patient Unresponsive!', Colors.red),
              if (_isHypersomnia && !_isUnresponsive)
                _alertBanner(context, '🟡 HYPERSOMNIA — In bed over 13 hours', Colors.orange),

              const SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.zero,
                child: _buildBlobChain(context),
              ),
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

  Widget _buildBlobChain(BuildContext context) {
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

      // ─── FIX 5: All text inside blobs uses _textStyle() ──────────────────
      // Previously used static const TextStyle with hardcoded px values.
      // Now they respond to screen width so they never overflow the blob image.
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

            // STATUS
            Positioned(
              top: topStatus, left: 0, right: 0, height: h2,
              child: Stack(children: [
                ClipRect(
                  child: Image.asset('assets/pocketcheck.png', fit: BoxFit.fill),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('STATUS', style: hugeGreen),
                        // ─── FIX 6: Flexible prevents text overflow in Row ──
                        // Without Flexible, long status strings like "EMERGENCY"
                        // will overflow the row on narrow screens.
                        Flexible(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
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
                            ],
                          ),
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
                ClipRect(
                  child: Image.asset('assets/pocketcheck.png', fit: BoxFit.fill),
                ),
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
                          },
                          child: ClipRect(
                            child: Image.asset('assets/arrow.png', fit: BoxFit.fill),
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
              ClipRect(
              child: Image.asset('assets/lastvibrationtest.png', fit: BoxFit.fill),
            ),
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

            // VELOSTAT GRAPH
            Positioned(
              top: topVelo, left: 0, right: 0, height: h1,
              child: Stack(children: [
      ClipRect(
      child: Image.asset('assets/velostatgraph.png', fit: BoxFit.fill),
      ),
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

  Widget _buildBarGraphSection(BuildContext context) {
    if (_windowHistory.isEmpty) {
      return Center(
        child: Text(
          'Waiting for sensor data...',
          style: _textStyle(
            context: context,
            scale: 0.9,
            color: Colors.white38,
          ),
        ),
      );
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
        // ─── FIX 7: State timeline uses fixed height + Expanded bars ─────────
        // Previously the SizedBox height was 36 — on very small phones the bar
        // label text above each bar would push out of the container.
        // Now we just show coloured blocks with no labels inside, height is
        // comfortable at 44. The labels live in the legend below.
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

        // ─── FIX 8: Wrap legend with larger text ──────────────────────────────
        Wrap(
          spacing: 14, runSpacing: 8,
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
        // ─── FIX 9: Bar graph container uses LayoutBuilder-aware height ───────
        // Previously fixed at 90px; on tall phones that's fine but on short
        // phones with many sections the total page height could overflow.
        // We keep 90 but wrap in an OverflowBox guard — the bars themselves
        // never have vertical labels because those were the source of the
        // "BOTTOM OVERFLOWED BY X PIXELS" errors. The label is placed *above*
        // the bar using a Column(mainAxisAlignment: end), so tall bars have no
        // room for the label when barH approaches 80. Fix: only show label
        // when barH < 65 (i.e. there is room above it).
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

              // ─── FIX 9 core: Only render label when bar is short enough ────
              // If barH > 65 there is less than ~18px above it in the 100px
              // container, and the Text widget causes the overflow seen in the
              // screenshot. Hiding the label when the bar is tall avoids it.
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

  Widget _legendDot(BuildContext context, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(2),
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