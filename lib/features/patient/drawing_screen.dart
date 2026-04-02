import 'package:flutter/material.dart';
import 'package:neuroguard/core/models/stroke_point.dart';
import 'drawing_canvas.dart';
import 'package:neuroguard/core/services/cognitest_service.dart';
import 'result_screen.dart';

class DrawingScreen extends StatefulWidget {
  final String patientId;

  const DrawingScreen({super.key, required this.patientId});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  final List<StrokePoint> _points = [];
  final _service = CogniTestService();
  bool _isSaving = false;

  void _addPoint(StrokePoint point) {
    // NO setState here — DrawingCanvas handles its own repaints
    // via ValueNotifier. Adding setState here was causing the entire
    // screen (AppBar, banner, FAB) to rebuild on every touch move event.
    _points.add(point);
  }

  Future<void> _finishTest() async {
    if (_points.where((p) => p.isDown).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please draw something first!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final avgTia = _service.calculateTimeInAir(_points);
    final score = _service.calculateScore(avgTia);
    final savedPoints = List<StrokePoint>.from(_points);

    final sessionId = await _service.saveSession(
      patientId: widget.patientId,
      points: savedPoints,
      avgTimeInAir: avgTia,
      score: score,
      completed: true,
    );

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          points: savedPoints,
          avgTimeInAir: avgTia,
          score: score,
          patientId: widget.patientId,
          sessionId: sessionId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B4FD4),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Fix the Station Clock 🕐',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              ),
            )
          else
            TextButton.icon(
              onPressed: _finishTest,
              icon: const Icon(Icons.check, color: Colors.white, size: 20),
              label: const Text(
                'Done',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),

      body: Column(
        children: [
          // Instruction banner
          Container(
            width: double.infinity,
            color: const Color(0xFFCCFF00),
            padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: const Text(
              'Draw a clock showing 10:10.\nDraw the circle, numbers, and hands.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Drawing area — fills remaining space
          Expanded(
            child: DrawingCanvas(
              points: _points,
              onPoint: _addPoint,
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _points.clear();
          // Need setState here only to reset the canvas
          setState(() {});
        },
        backgroundColor: Colors.red.shade400,
        icon: const Icon(Icons.refresh, color: Colors.white),
        label: const Text('Clear', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
