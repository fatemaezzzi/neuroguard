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
  // ── Touch handlers ─────────────────────────────────────────────────
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
        // BUG FIX 1: white background set on Container OUTSIDE CustomPaint
        // Previously Container(color: white) was the CHILD of CustomPaint
        // which rendered ON TOP of the painter, hiding all strokes.
        color: Colors.white,
        child: CustomPaint(
          painter: _ClockCanvasPainter(widget.points),
          // SizedBox.expand forces the painter to fill all available space
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ── Painter ────────────────────────────────────────────────────────────────
class _ClockCanvasPainter extends CustomPainter {
  final List<StrokePoint> points;
  _ClockCanvasPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius =
        (size.width < size.height ? size.width : size.height) / 2 - 16;

    // ── Clock circle ──────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0,
    );

    // Center dot
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill,
    );

    // ── Pen strokes (dark blue so clearly visible on white) ───────────
    final strokePaint = Paint()
      ..color = const Color(0xFF1B1464) // dark navy — very visible on white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

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

    // ── Pen cursor dot at last touch position ─────────────────────────
    if (points.isNotEmpty && points.last.isDown) {
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
  bool shouldRepaint(_ClockCanvasPainter old) => true;
}