import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'cognitest_history_screen.dart';
import 'package:neuroguard/features/shared/settings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReportsPage
//
// Wired to Firestore. Accepts a required patientId.
//
// Live streams (StreamBuilder):
//   • Bed status   → sleepSessions/{patientId}/windows/  (latest doc, state field: "ON_BED"/"OFF_BED")
//   • Alert logs   → alerts/{patientId}/entries/         (5 most recent, ordered by timestamp desc)
//
// One-shot reads (FutureBuilder):
//   • Cognitive last/prev test  → users/{patientId}/cognitest_sessions/ (top 2 by timestamp desc)
//   • Cognitive chart           → users/{patientId}/cognitest_sessions/ (top 5 by timestamp desc)
//   • Weekly summary            → sleepSessions/{patientId}/dailySummaries/ (last 7 days)
//                               + cognitest_sessions (last 7 days)
// ─────────────────────────────────────────────────────────────────────────────
class ReportsPage extends StatefulWidget {
  final String patientId;

  const ReportsPage({super.key, required this.patientId});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _db = FirebaseFirestore.instance;

  // ── Firestore streams (initialised in initState, never re-created) ──────────
  late final Stream<QuerySnapshot> _bedWindowStream;
  late final Stream<QuerySnapshot> _alertStream;

  // ── One-shot futures (initialised in initState) ─────────────────────────────
  late final Future<List<QueryDocumentSnapshot>> _cogniSessionsFuture;
  late final Future<_WeeklySummaryData> _weeklySummaryFuture;

  // Disposed guard — prevents setState after dispose
  bool _disposed = false;

  // ── Text styles (unchanged from original) ──────────────────────────────────
  static const TextStyle _bigBlack = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 28,
    letterSpacing: 1.0,
    color: Colors.black,
  );

  static const TextStyle _bigGreen = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 28,
    letterSpacing: 1.5,
    color: Color(0xFFCCFF00),
  );

  static const TextStyle _bigPurple = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 28,
    letterSpacing: 1,
    color: Color(0xFF7C3AED),
  );

  static const TextStyle _medBlack = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 15,
    letterSpacing: 1,
    color: Colors.black,
  );

  static const TextStyle _medWhite = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 15,
    letterSpacing: 1,
    color: Colors.white,
  );

  static const TextStyle _numberWhite = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 42,
    color: Colors.white,
  );

  static const TextStyle _numberBlack = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 42,
    color: Colors.black,
  );

  static const TextStyle _timeGreen = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: Color(0xFFCCFF00),
  );

  static const TextStyle _alertText = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 26,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final pid = widget.patientId;

    // Live stream: latest bed window (order by epochTimestamp desc, limit 1)
    // epochTimestamp is a number field (not a Firestore Timestamp)
    _bedWindowStream = _db
        .collection('sleepSessions')
        .doc(pid)
        .collection('windows')
        .orderBy('epochTimestamp', descending: true)
        .limit(1)
        .snapshots();

    // Live stream: 5 most recent alerts
    _alertStream = _db
        .collection('alerts')
        .doc(pid)
        .collection('entries')
        .orderBy('timestamp', descending: true)
        .limit(5)
        .snapshots();

    // One-shot: top 5 cognitest sessions (we use top 2 for last/prev, all 5 for chart)
    _cogniSessionsFuture = _db
        .collection('users')
        .doc(pid)
        .collection('cognitest_sessions')
        .orderBy('timestamp', descending: true)
        .limit(5)
        .get()
        .then((snap) => snap.docs);

    // One-shot: weekly summary data
    _weeklySummaryFuture = _loadWeeklySummary(pid);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ── Weekly summary loader ───────────────────────────────────────────────────

  Future<_WeeklySummaryData> _loadWeeklySummary(String patientId) async {
    // dailySummaries doc IDs are date strings: "YYYY-MM-DD"
    // We filter by doc ID range — no Timestamp comparison needed.
    final cutoffDate = DateTime.now().subtract(const Duration(days: 7));
    final cutoffStr =
        '${cutoffDate.year}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}';
    final todayStr =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';

    // Firestore string ordering works correctly for ISO date strings
    final sleepSnap = await _db
        .collection('sleepSessions')
        .doc(patientId)
        .collection('dailySummaries')
        .orderBy(FieldPath.documentId)
        .startAt([cutoffStr])
        .endAt(['$todayStr\uf8ff'])
        .get();

    // Cognitest sessions — these still use a real Timestamp field
    final cogniCutoff = Timestamp.fromDate(cutoffDate);
    final cogniSnap = await _db
        .collection('users')
        .doc(patientId)
        .collection('cognitest_sessions')
        .where('timestamp', isGreaterThan: cogniCutoff)
        .get();

    // Alert count — also uses real Timestamp field
    final alertSnap = await _db
        .collection('alerts')
        .doc(patientId)
        .collection('entries')
        .where('timestamp', isGreaterThan: cogniCutoff)
        .get();

    // ── Aggregate sleep data ──────────────────────────────────────────────────
    // Fields confirmed from Firestore schema:
    //   totalBedMinutes (number) — convert to hours for display
    //   No avgBedOccupancyRatio field — occupancy derived from totalBedMinutes
    double totalBedMinutes = 0;
    int nightsMonitored = sleepSnap.docs.length;

    for (final doc in sleepSnap.docs) {
      final data = doc.data();
      totalBedMinutes +=
          (data['totalBedMinutes'] as num?)?.toDouble() ?? 0.0;
    }

    // Average sleep hours per night (totalBedMinutes / 60 / nights)
    final avgSleepHours = nightsMonitored > 0
        ? (totalBedMinutes / 60.0) / nightsMonitored
        : 0.0;

    // Occupancy % = avg minutes in bed per night out of 8h (480 min) target
    final avgOccupancyPct = nightsMonitored > 0
        ? ((totalBedMinutes / nightsMonitored) / 480.0 * 100).clamp(0, 100)
        : 0.0;

    // ── Aggregate cognitest data ──────────────────────────────────────────────
    double totalAvgTia = 0;
    final cogniDocs = cogniSnap.docs;
    for (final doc in cogniDocs) {
      totalAvgTia +=
          (doc.data()['avg_time_in_air'] as num?)?.toDouble() ?? 0.0;
    }
    final avgHoverTime =
    cogniDocs.isNotEmpty ? totalAvgTia / cogniDocs.length : 0.0;

    return _WeeklySummaryData(
      avgHoverTime: avgHoverTime,
      avgSleepHours: avgSleepHours,
      alertCount: alertSnap.docs.length,
      avgOccupancyPct: avgOccupancyPct.toDouble(),
      nightsMonitored: nightsMonitored,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: CaregiverBottomNav(
        onSettingsTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        },
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              _buildSleepReport(),
              const SizedBox(height: 20),
              _buildCognitiveReport(),
              const SizedBox(height: 20),
              _buildWeeklySummary(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── SLEEP REPORT ──────────────────────────────────────────────────────────

  Widget _buildSleepReport() {
    return LayoutBuilder(builder: (context, constraints) {
      final double w = constraints.maxWidth;
      final double sh = w * (61 / 342);

      // No fixed height — content drives the card height.
      // The background image stretches vertically to match.
      return Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/sleepreport.png', fit: BoxFit.fill),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Text('SLEEP REPORT', style: _bigBlack),
                    SizedBox(width: 8),
                    Text('🌧️', style: TextStyle(fontSize: 22)),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Bed status (live StreamBuilder) ─────────────────────
                StreamBuilder<QuerySnapshot>(
                  stream: _bedWindowStream,
                  builder: (context, snap) {
                    String statusLabel = '—';
                    TextStyle statusStyle = _bigBlack;

                    if (snap.hasData && snap.data!.docs.isNotEmpty) {
                      final data = snap.data!.docs.first.data()
                      as Map<String, dynamic>;
                      final state = data['state'] as String?;
                      final bool isOccupied;
                      if (state != null) {
                        isOccupied = state == 'ON_BED';
                      } else {
                        final ratio =
                            (data['bedOccupancyRatio'] as num?)?.toDouble() ??
                                0.0;
                        isOccupied = ratio > 0.5;
                      }
                      statusLabel = isOccupied ? 'OCCUPIED' : 'VACANT';
                      statusStyle = isOccupied ? _bigPurple : _bigBlack;
                    } else if (snap.hasError) {
                      statusLabel = 'ERROR';
                    }

                    return SizedBox(
                      width: w - 40,
                      height: sh,
                      child: Stack(
                        children: [
                          Image.asset('assets/statusbed.png',
                              width: w - 40, height: sh, fit: BoxFit.fill),
                          Positioned.fill(
                            child: Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text('STATUS', style: _bigBlack),
                                  Text(statusLabel,
                                      textAlign: TextAlign.right,
                                      style: statusStyle),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 14),
                const Text('ALERT LOGS', style: _bigGreen),
                const SizedBox(height: 8),

                // ── Alert logs (live StreamBuilder) ─────────────────────
                StreamBuilder<QuerySnapshot>(
                  stream: _alertStream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const Text('Could not load alerts.',
                          style: TextStyle(color: Colors.white54));
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return const Text('No recent alerts.',
                          style: TextStyle(
                              color: Colors.white54,
                              fontFamily: 'Roboto',
                              fontSize: 14));
                    }

                    final docs = snap.data!.docs;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final ts = data['timestamp'] as Timestamp?;
                        final message = data['message'] as String? ?? 'Alert';
                        final timeLabel =
                        ts != null ? _formatTime(ts.toDate()) : '--:--';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(timeLabel,
                                  style: _timeGreen.copyWith(fontSize: 15)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(message,
                                    style: _alertText.copyWith(fontSize: 15)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ── COGNITIVE TEST REPORT ─────────────────────────────────────────────────

  Widget _buildCognitiveReport() {
    return LayoutBuilder(builder: (context, constraints) {
      final double w = constraints.maxWidth;

      return SizedBox(
        width: w,
        child: Stack(
          children: [
            Image.asset('assets/cognitivetestreport.png',
                width: w, fit: BoxFit.fitWidth),
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              bottom: 20,
              child: FutureBuilder<List<QueryDocumentSnapshot>>(
                future: _cogniSessionsFuture,
                builder: (context, snap) {
                  // ── Parse sessions ──────────────────────────────────────
                  String lastTest = '—';
                  String prevTest = '—';
                  List<FlSpot> chartSpots = _fallbackSpots();

                  if (snap.hasData && snap.data!.isNotEmpty) {
                    final docs = snap.data!;

                    // Last test = most recent (index 0)
                    final lastTia = (docs[0].data()
                    as Map<String, dynamic>)['avg_time_in_air']
                    as num?;
                    if (lastTia != null) {
                      lastTest = '${lastTia.toStringAsFixed(1)}s';
                    }

                    // Previous test = second most recent (index 1)
                    if (docs.length >= 2) {
                      final prevTia = (docs[1].data()
                      as Map<String, dynamic>)['avg_time_in_air']
                      as num?;
                      if (prevTia != null) {
                        prevTest = '${prevTia.toStringAsFixed(1)}s';
                      }
                    } else {
                      prevTest = 'N/A';
                    }

                    // Chart: up to 5 sessions, oldest → newest (reverse order)
                    // We received them newest-first, so we reverse for left→right display.
                    final chartDocs = docs.reversed.toList();
                    chartSpots = List.generate(chartDocs.length, (i) {
                      final tia = (chartDocs[i].data()
                      as Map<String, dynamic>)['avg_time_in_air']
                      as num?;
                      return FlSpot(
                          (i + 1).toDouble(), tia?.toDouble() ?? 0.0);
                    });
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('COGNITIVE TEST REPORT', style: _bigBlack),
                      const SizedBox(height: 14),
                      _buildTestBoxes(w - 40,
                          lastTest: lastTest, prevTest: prevTest),
                      const SizedBox(height: 16),
                      const Text('HOVER TIME OVER LAST 5\nSESSIONS',
                          style: _bigBlack),
                      const SizedBox(height: 10),
                      Container(
                        height: 180,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0D0D),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
                        ),
                        padding: const EdgeInsets.fromLTRB(8, 14, 14, 8),
                        child: snap.connectionState == ConnectionState.waiting
                            ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFCCFF00)))
                            : _buildHoverChart(chartSpots),
                      ),
                      const SizedBox(height: 14),
                      // ── View Full History button ──────────────────────
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CogniTestHistoryScreen(
                              patientId: widget.patientId,
                            ),
                          ),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: const Color(0xFF7C3AED), width: 1.5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text(
                                'VIEW FULL HISTORY',
                                style: TextStyle(
                                  fontFamily: 'MicrosoftSansSerifBold',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 1.2,
                                  color: Colors.white,
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  color: Color(0xFF7C3AED), size: 22),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }

  List<FlSpot> _fallbackSpots() => [
    const FlSpot(1, 2.5),
    const FlSpot(2, 3.0),
    const FlSpot(3, 2.7),
    const FlSpot(4, 3.3),
    const FlSpot(5, 2.8),
  ];

  Widget _buildTestBoxes(double w,
      {required String lastTest, required String prevTest}) {
    final double ptH = w * (94 / 342);
    final double ltW = w * 0.30;
    final double ltH = ltW;

    return SizedBox(
      width: w,
      height: ltH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Previous test (background strip)
          Positioned(
            top: ltH / 2 - ptH / 2,
            left: 0,
            right: 0,
            height: ptH,
            child: Stack(
              children: [
                Image.asset('assets/previoustest.png',
                    width: w, height: ptH, fit: BoxFit.fill),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PREVIOUS TEST', style: _medBlack),
                            const SizedBox(height: 2),
                            Text(prevTest, style: _numberBlack),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Last test (foreground purple box)
          Positioned(
            top: 0,
            left: 0,
            width: ltW,
            height: ltH,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.fromLTRB(14, 16, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('LAST TEST', style: _medWhite),
                  Text(lastTest, style: _numberWhite),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoverChart(List<FlSpot> spots) {
    if (spots.isEmpty) spots = _fallbackSpots();

    final allY = spots.map((s) => s.y).toList();
    final minY = (allY.reduce((a, b) => a < b ? a : b) - 0.5)
        .clamp(0.0, double.infinity);
    final maxY = allY.reduce((a, b) => a > b ? a : b) + 0.5;

    const limeGreen = Color(0xFFCCFF00);
    const axisLabel = TextStyle(fontSize: 11, color: Colors.white38, fontFamily: 'Roboto');

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.5,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.white.withValues(alpha: 0.08), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) =>
                  Text(v.toInt().toString(), style: axisLabel),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 0.5,
              reservedSize: 38,
              getTitlesWidget: (v, _) =>
                  Text('${v.toStringAsFixed(1)}s', style: axisLabel),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 1,
        maxX: spots.length.toDouble(),
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: limeGreen,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                radius: 4,
                color: limeGreen,
                strokeWidth: 2,
                strokeColor: Colors.black,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  limeGreen.withValues(alpha: 0.25),
                  limeGreen.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── WEEKLY SUMMARY ─────────────────────────────────────────────────────────

  Widget _buildWeeklySummary() {
    return FutureBuilder<_WeeklySummaryData>(
      future: _weeklySummaryFuture,
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final d = snap.data;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.5), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header strip ─────────────────────────────────────────
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF7C3AED),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(
                  children: const [
                    Text(
                      'WEEKLY SUMMARY',
                      style: TextStyle(
                        fontFamily: 'MicrosoftSansSerifBold',
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    Spacer(),
                    Text('7 DAYS', style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 12,
                      color: Colors.white60,
                      letterSpacing: 1,
                    )),
                  ],
                ),
              ),

              // ── Stats grid ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: loading
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator(
                        color: Color(0xFFCCFF00)),
                  ),
                )
                    : snap.hasError || d == null
                    ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Could not load weekly data.',
                        style: TextStyle(color: Colors.white38)),
                  ),
                )
                    : Column(
                  children: [
                    // Row 1
                    Row(children: [
                      Expanded(
                          child: _summaryTile(
                              icon: Icons.timer_outlined,
                              label: 'AVG HOVER TIME',
                              value: d.avgHoverTime > 0
                                  ? '${d.avgHoverTime.toStringAsFixed(1)}s'
                                  : '—',
                              accent: const Color(0xFFCCFF00))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _summaryTile(
                              icon: Icons.bedtime_outlined,
                              label: 'AVG SLEEP',
                              value: d.avgSleepHours > 0
                                  ? '${d.avgSleepHours.toStringAsFixed(1)}h'
                                  : '—',
                              accent: const Color(0xFF7C3AED))),
                    ]),
                    const SizedBox(height: 12),
                    // Row 2
                    Row(children: [
                      Expanded(
                          child: _summaryTile(
                              icon: Icons.notifications_outlined,
                              label: 'ALERTS',
                              value: d.alertCount.toString(),
                              accent: const Color(0xFFFF4C4C))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _summaryTile(
                              icon: Icons.hotel_outlined,
                              label: 'BED OCCUPANCY',
                              value: d.avgOccupancyPct > 0
                                  ? '${d.avgOccupancyPct.toStringAsFixed(0)}%'
                                  : '—',
                              accent: const Color(0xFFCCFF00))),
                    ]),
                    const SizedBox(height: 12),
                    // Row 3 — full width
                    _summaryTile(
                        icon: Icons.nights_stay_outlined,
                        label: 'NIGHTS MONITORED',
                        value: d.nightsMonitored.toString(),
                        accent: const Color(0xFF7C3AED),
                        fullWidth: true),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summaryTile({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
    bool fullWidth = false,
  }) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                    fontFamily: 'MicrosoftSansSerifBold',
                    fontSize: 10,
                    color: accent,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                    fontFamily: 'MicrosoftSansSerifBold',
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: Colors.white,
                  )),
            ],
          ),
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Data class for weekly summary aggregation result
// ─────────────────────────────────────────────────────────────────────────────
class _WeeklySummaryData {
  final double avgHoverTime;
  final double avgSleepHours;
  final int alertCount;
  final double avgOccupancyPct;
  final int nightsMonitored;

  const _WeeklySummaryData({
    required this.avgHoverTime,
    required this.avgSleepHours,
    required this.alertCount,
    required this.avgOccupancyPct,
    required this.nightsMonitored,
  });
}