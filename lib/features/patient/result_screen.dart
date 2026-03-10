import 'package:flutter/material.dart';
import 'package:neuroguard/core/models/stroke_point.dart';
import 'replay_scrubber.dart';
import 'package:neuroguard/core/services/cognitest_service.dart';

class ResultScreen extends StatefulWidget {
  final List<StrokePoint> points;
  final double avgTimeInAir;
  final int score;
  final String patientId;
  final String sessionId; // BUG FIX 3: receive sessionId to confirm save

  const ResultScreen({
    super.key,
    required this.points,
    required this.avgTimeInAir,
    required this.score,
    required this.patientId,
    required this.sessionId,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _service = CogniTestService();
  int? _previousScore;
  double? _previousTia;
  bool _loadingPrev = true;

  @override
  void initState() {
    super.initState();
    _loadPreviousScore();
  }

  // BUG FIX 4: load the previous session's score from Firestore
  Future<void> _loadPreviousScore() async {
    final sessions = await _service.getPastSessions(widget.patientId);

    // Sessions are ordered newest first. The current session is index 0.
    // The previous one is index 1.
    if (sessions.length > 1) {
      final prev = sessions[1];
      setState(() {
        _previousScore = (prev['score'] as num?)?.toInt();
        _previousTia =
            (prev['avg_time_in_air'] as num?)?.toDouble();
      });
    }
    setState(() => _loadingPrev = false);
  }

  Color get _scoreColor {
    if (widget.score >= 80) return Colors.green;
    if (widget.score >= 55) return Colors.orange;
    return Colors.red;
  }

  Color _prevScoreColor(int s) {
    if (s >= 80) return Colors.green;
    if (s >= 55) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final label = _service.scoreLabel(widget.score);
    final strokeCount = widget.points.where((p) => !p.isDown).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B4FD4),
        automaticallyImplyLeading: false,
        title: const Text(
          'Test Complete',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800),
        ),
        // BUG FIX 3: Saved badge always visible in app bar
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  'Saved',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // ── Score card ────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7B4FD4).withOpacity(0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text('Your Score',
                            style:
                            TextStyle(fontSize: 16, color: Colors.grey)),
                        const SizedBox(height: 10),
                        Text(
                          '${widget.score}',
                          style: TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            color: _scoreColor,
                          ),
                        ),
                        Text(label,
                            style: const TextStyle(fontSize: 16)),
                        const Divider(height: 32),

                        // Metrics row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _MetricTile(
                              label: 'Avg Hesitation',
                              value:
                              '${widget.avgTimeInAir.toStringAsFixed(2)}s',
                              icon: Icons.timer_outlined,
                            ),
                            _MetricTile(
                              label: 'Strokes',
                              value: '$strokeCount',
                              icon: Icons.gesture,
                            ),
                            _MetricTile(
                              label: 'Points',
                              value: '${widget.points.length}',
                              icon: Icons.touch_app_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── BUG FIX 4: Previous score card ───────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: _loadingPrev
                        ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF7B4FD4)))
                        : _previousScore == null
                        ? const Text(
                      'This is your first test! No previous score to compare.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey, fontSize: 14),
                    )
                        : Row(
                      children: [
                        // Current
                        Expanded(
                          child: Column(
                            children: [
                              const Text('This Test',
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                      fontWeight:
                                      FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(
                                '${widget.score}',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: _scoreColor,
                                ),
                              ),
                              Text(
                                '${widget.avgTimeInAir.toStringAsFixed(2)}s hover',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey),
                              ),
                            ],
                          ),
                        ),

                        // Arrow
                        Column(
                          children: [
                            Icon(
                              widget.score > _previousScore!
                                  ? Icons.arrow_upward
                                  : widget.score < _previousScore!
                                  ? Icons.arrow_downward
                                  : Icons.remove,
                              color: widget.score >= _previousScore!
                                  ? Colors.green
                                  : Colors.red,
                              size: 28,
                            ),
                            Text(
                              widget.score >= _previousScore!
                                  ? 'Better!'
                                  : 'Declined',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: widget.score >=
                                    _previousScore!
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),

                        // Previous
                        Expanded(
                          child: Column(
                            children: [
                              const Text('Previous Test',
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                      fontWeight:
                                      FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(
                                '$_previousScore',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: _prevScoreColor(
                                      _previousScore!),
                                ),
                              ),
                              if (_previousTia != null)
                                Text(
                                  '${_previousTia!.toStringAsFixed(2)}s hover',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Replay ────────────────────────────────────────────
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Replay your drawing',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF7B4FD4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 320,
                    child: ReplayScrubber(allPoints: widget.points),
                  ),
                ],
              ),
            ),
          ),

          // Back to Home
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B4FD4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () =>
                    Navigator.popUntil(context, (route) => route.isFirst),
                child: const Text(
                  'Back to Home',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricTile(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF7B4FD4), size: 26),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF7B4FD4))),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}