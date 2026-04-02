import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neuroguard/features/caregiver/caregiver_home.dart';
import 'package:neuroguard/features/patient/patient_home.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'package:neuroguard/core/services/cognitest_service.dart';
import 'package:neuroguard/core/models/stroke_point.dart';
import 'package:neuroguard/features/patient/replay_scrubber.dart';
import 'package:neuroguard/features/shared/settings_screen.dart';

class CogniTestHistoryScreen extends StatefulWidget {
  final String callerRole;

  const CogniTestHistoryScreen({
    super.key,
    this.callerRole = 'caregiver',
  });

  @override
  State<CogniTestHistoryScreen> createState() =>
      _CogniTestHistoryScreenState();
}

class _CogniTestHistoryScreenState extends State<CogniTestHistoryScreen> {
  final String _patientId = FirebaseAuth.instance.currentUser?.uid ?? 'patient_01';

  final _service = CogniTestService();
  bool _showMonthly = false;
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String? _expandedSessionId;
  List<StrokePoint> _replayPoints = [];
  bool _loadingReplay = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    final sessions = await _service.getPastSessions(_patientId);
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  Future<void> _toggleSession(String sessionId) async {
    if (_expandedSessionId == sessionId) {
      setState(() {
        _expandedSessionId = null;
        _replayPoints = [];
      });
      return;
    }
    setState(() {
      _expandedSessionId = sessionId;
      _replayPoints = [];
      _loadingReplay = true;
    });
    final points = await _service.getSessionPoints(_patientId, sessionId);
    setState(() {
      _replayPoints = points;
      _loadingReplay = false;
    });
  }

  void _goHome() {
    if (widget.callerRole == 'patient') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const PatientHome()),
            (route) => false,
      );
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CaregiverHomePage()),
            (route) => false,
      );
    }
  }

  void _goSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  List<FlSpot> _buildSpots() {
    final chronological = _sessions.reversed.toList();
    return List.generate(chronological.length, (i) {
      final tia =
          (chronological[i]['avg_time_in_air'] as num?)?.toDouble() ?? 0.0;
      return FlSpot(i.toDouble() + 1, tia);
    });
  }

  double get _chartMinY {
    if (_sessions.isEmpty) return 0;
    final vals =
    _sessions.map((s) => (s['avg_time_in_air'] as num?)?.toDouble() ?? 0.0);
    return (vals.reduce((a, b) => a < b ? a : b) - 0.5).clamp(0.0, 99.0);
  }

  double get _chartMaxY {
    if (_sessions.isEmpty) return 5;
    final vals =
    _sessions.map((s) => (s['avg_time_in_air'] as num?)?.toDouble() ?? 0.0);
    return vals.reduce((a, b) => a > b ? a : b) + 0.5;
  }

  Color _scoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 55) return Colors.orange;
    return Colors.red;
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.day}/${dt.month}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final isPatient = widget.callerRole == 'patient';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'TEST HISTORY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _loadSessions,
                    child: const Icon(Icons.refresh,
                        color: Color(0xFFCCFF00), size: 24),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: _loading
                  ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF7B4FD4)))
                  : _sessions.isEmpty
                  ? _buildEmptyState()
                  : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 8),
                child: Column(
                  children: [
                    _buildSummaryPills(),
                    const SizedBox(height: 20),
                    _buildToggle(),
                    const SizedBox(height: 12),
                    _buildTrendGraph(),
                    const SizedBox(height: 24),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'PAST SESSIONS',
                        style: TextStyle(
                          color: Color(0xFFCCFF00),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._sessions.map(_buildSessionRow),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ── Bottom Nav ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: isPatient
                  ? PatientBottomNav(
                onHomeTap: _goHome,
                onSettingsTap: _goSettings,
              )
                  : CaregiverBottomNav(
                onHomeTap: _goHome,
                onSettingsTap: _goSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.history_toggle_off, color: Colors.grey, size: 64),
        SizedBox(height: 16),
        Text('No tests yet',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text(
          'Complete a clock drawing test\nto see results here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ],
    ),
  );

  Widget _buildSummaryPills() {
    final latest = _sessions.isNotEmpty ? _sessions[0] : null;
    final prev = _sessions.length > 1 ? _sessions[1] : null;
    final latestTia =
        (latest?['avg_time_in_air'] as num?)?.toStringAsFixed(2) ?? '—';
    final prevTia =
        (prev?['avg_time_in_air'] as num?)?.toStringAsFixed(2) ?? '—';
    final latestScore = (latest?['score'] as num?)?.toInt() ?? 0;
    final prevScore = (prev?['score'] as num?)?.toInt();

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LAST TEST',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1)),
                const SizedBox(height: 6),
                Text('${latestTia}s',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 32)),
                const SizedBox(height: 4),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _scoreColor(latestScore),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Score: $latestScore',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PREVIOUS TEST',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1)),
                const SizedBox(height: 6),
                Text(
                  prevScore != null ? '$prevScore' : '—',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color:
                    prevScore != null ? _scoreColor(prevScore) : Colors.grey,
                  ),
                ),
                Text(
                  prevScore != null
                      ? '${prevTia}s hover'
                      : 'No previous test',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (prevScore != null)
                  Row(
                    children: [
                      Icon(
                        latestScore >= prevScore
                            ? Icons.trending_up
                            : Icons.trending_down,
                        color: latestScore >= prevScore
                            ? Colors.green
                            : Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        latestScore >= prevScore ? 'Improved' : 'Declined',
                        style: TextStyle(
                          fontSize: 11,
                          color: latestScore >= prevScore
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggle() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(children: [
      _toggleBtn('Weekly', !_showMonthly,
              () => setState(() => _showMonthly = false)),
      _toggleBtn('Monthly', _showMonthly,
              () => setState(() => _showMonthly = true)),
    ]),
  );

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF7B4FD4) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    ),
  );

  Widget _buildTrendGraph() {
    final spots = _buildSpots();
    if (spots.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 14, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              'HOVER TIME TREND (seconds)',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: Colors.black87,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 0.5,
                  verticalInterval: 1,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: Colors.grey.shade300, strokeWidth: 1),
                  getDrawingVerticalLine: (_) =>
                      FlLine(color: Colors.grey.shade200, strokeWidth: 0.5),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('#${v.toInt()}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 0.5,
                      reservedSize: 40,
                      getTitlesWidget: (v, _) => Text(
                          '${v.toStringAsFixed(1)}s',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54)),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey.shade300)),
                minX: 1,
                maxX: spots.length.toDouble(),
                minY: _chartMinY,
                maxY: _chartMaxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFF7B4FD4),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, pct, bar, idx) =>
                          FlDotCirclePainter(
                            radius: 5,
                            color: const Color(0xFF7B4FD4),
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF7B4FD4).withOpacity(0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(Map<String, dynamic> session) {
    final sessionId = session['session_id'] as String;
    final tia =
        (session['avg_time_in_air'] as num?)?.toStringAsFixed(2) ?? '—';
    final score = (session['score'] as num?)?.toInt() ?? 0;
    final ts = session['timestamp'];
    final isExpanded = _expandedSessionId == sessionId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: isExpanded
            ? Border.all(color: const Color(0xFF7B4FD4), width: 1.5)
            : null,
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _toggleSession(sessionId),
            child: Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _scoreColor(score),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text('$score',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_formatDate(ts),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 3),
                        Text('Hover time: ${tia}s',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B4FD4).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF7B4FD4), width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isExpanded ? Icons.stop : Icons.play_arrow,
                          color: const Color(0xFF7B4FD4),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isExpanded ? 'Close' : 'Replay',
                          style: const TextStyle(
                              color: Color(0xFF7B4FD4),
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const Divider(color: Color(0xFF333333)),
                  const SizedBox(height: 8),
                  if (_loadingReplay)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        children: [
                          CircularProgressIndicator(
                              color: Color(0xFF7B4FD4)),
                          SizedBox(height: 12),
                          Text('Loading drawing...',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  else if (_replayPoints.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Drawing still saving, try again in a moment.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    SizedBox(
                      height: 340,
                      child: ReplayScrubber(allPoints: _replayPoints),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}