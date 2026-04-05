import 'package:flutter/material.dart';
import 'package:neuroguard/core/models/stroke_point.dart';
import 'replay_scrubber.dart';
import 'package:neuroguard/core/services/cognitest_service.dart';

class ResultScreen extends StatelessWidget {
  final List<StrokePoint> points;
  final double avgTimeInAir;
  final int score;
  final String patientId;
  final String sessionId;
  final int? previousScore;
  final double? previousTia;

  const ResultScreen({
    super.key,
    required this.points,
    required this.avgTimeInAir,
    required this.score,
    required this.patientId,
    required this.sessionId,
    this.previousScore,
    this.previousTia,
  });

  Color get _scoreColor {
    if (score >= 80) return Colors.green;
    if (score >= 55) return Colors.orange;
    return Colors.red;
  }

  Color _prevScoreColor(int s) {
    if (s >= 80) return Colors.green;
    if (s >= 55) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final service = CogniTestService();
    final label = service.scoreLabel(score);
    final strokeCount = points.where((p) => !p.isDown).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B4FD4),
        automaticallyImplyLeading: false,
        title: const Text('Test Complete',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(children: [
              Icon(Icons.cloud_done, color: Colors.white, size: 16),
              SizedBox(width: 4),
              Text('Saved',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
          ),
        ],
      ),

      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              color: const Color(0xFF7B4FD4),
              child: const TabBar(
                indicatorColor: Color(0xFFCCFF00),
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                tabs: [Tab(text: 'RESULTS'), Tab(text: 'REPLAY')],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // ── RESULTS tab ─────────────────────────────────────
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Score card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFF7B4FD4).withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 4))],
                          ),
                          child: Column(
                            children: [
                              const Text('Your Score', style: TextStyle(fontSize: 16, color: Colors.grey)),
                              const SizedBox(height: 10),
                              Text('$score', style: TextStyle(fontSize: 72, fontWeight: FontWeight.w900, color: _scoreColor)),
                              Text(label, style: const TextStyle(fontSize: 16)),
                              const Divider(height: 32),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _MetricTile(label: 'Avg Hesitation', value: '${avgTimeInAir.toStringAsFixed(2)}s', icon: Icons.timer_outlined),
                                  _MetricTile(label: 'Strokes', value: '$strokeCount', icon: Icons.gesture),
                                  _MetricTile(label: 'Points', value: '${points.length}', icon: Icons.touch_app_outlined),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Previous score — no loading spinner, data passed directly
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 3))],
                          ),
                          child: previousScore == null
                              ? const Text(
                            'This is your first test! No previous score to compare.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          )
                              : Row(
                            children: [
                              Expanded(
                                child: Column(children: [
                                  const Text('This Test', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  Text('$score', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: _scoreColor)),
                                  Text('${avgTimeInAir.toStringAsFixed(2)}s hover', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ]),
                              ),
                              Column(children: [
                                Icon(
                                  score > previousScore! ? Icons.arrow_upward : score < previousScore! ? Icons.arrow_downward : Icons.remove,
                                  color: score >= previousScore! ? Colors.green : Colors.red,
                                  size: 28,
                                ),
                                Text(
                                  score >= previousScore! ? 'Better!' : 'Declined',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: score >= previousScore! ? Colors.green : Colors.red),
                                ),
                              ]),
                              Expanded(
                                child: Column(children: [
                                  const Text('Previous Test', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  Text('$previousScore', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: _prevScoreColor(previousScore!))),
                                  if (previousTia != null)
                                    Text('${previousTia!.toStringAsFixed(2)}s hover', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ]),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7B4FD4),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                            child: const Text('Back to Home', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                  // ── REPLAY tab — full screen ─────────────────────────
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ReplayScrubber(allPoints: points),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _MetricTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: const Color(0xFF7B4FD4), size: 26),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF7B4FD4))),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
    ]);
  }
}