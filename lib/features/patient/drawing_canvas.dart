import 'package:flutter/material.dart';
import 'package:neuroguard/core/models/stroke_point.dart';

class DrawingCanvas extends StatefulWidget {
  final List<StrokePoint> points;
  final Function(StrokePoint) onPoint;
  final bool readOnly;

  const DrawingCanvas({
    super.key,
    required this.points,
    required this.onPoint,
    this.readOnly = false,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  void _handlePointerDown(PointerDownEvent e) {
    if (widget.readOnly) return;
    widget.onPoint(StrokePoint(
      x: e.localPosition.dx,
      y: e.localPosition.dy,
      pressure: e.pressure,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isDown: true,
    ));
  }

  void _handlePointerMove(PointerMoveEvent e) {
    if (widget.readOnly) return;
    widget.onPoint(StrokePoint(
      x: e.localPosition.dx,
      y: e.localPosition.dy,
      pressure: e.pressure,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isDown: true,
    ));
  }

  void _handlePointerUp(PointerUpEvent e) {
    if (widget.readOnly) return;
    widget.onPoint(StrokePoint(
      x: e.localPosition.dx,
      y: e.localPosition.dy,
      pressure: 0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isDown: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      child: Container(
        color: Colors.white,
        child: CustomPaint(
          painter: _ClockCanvasPainter(
            points: widget.points,
            showCursor: !widget.readOnly,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ClockCanvasPainter extends CustomPainter {
  final List<StrokePoint> points;
  final bool showCursor;

  _ClockCanvasPainter({required this.points, required this.showCursor});

  @override
  void paint(Canvas canvas, Size size) {
    // ── Stroke paint ────────────────────────────────────────────────
    final strokePaint = Paint()
      ..color = const Color(0xFF1B1464)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // ── Draw all strokes ────────────────────────────────────────────
    for (int i = 0; i < points.length - 1; i++) {
      final curr = points[i];
      final next = points[i + 1];
      if (curr.isDown && next.isDown) {
        canvas.drawLine(
          Offset(curr.x, curr.y),
          Offset(next.x, next.y),
          strokePaint,
        );
      }
    }

    // ── Pen cursor dot (only when drawing, not in replay) ──────────
    if (showCursor && points.isNotEmpty && points.last.isDown) {
      final last = points.last;
      canvas.drawCircle(
        Offset(last.x, last.y),
        7,
        Paint()
          ..color = const Color(0xFF7B4FD4)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(last.x, last.y),
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_ClockCanvasPainter old) =>
      old.points != points || old.showCursor != showCursor;
}