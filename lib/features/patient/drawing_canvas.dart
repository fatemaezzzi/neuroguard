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
  // ValueNotifier triggers ONLY the CustomPaint to repaint —
  // not the entire widget tree. This is the key fix for lag.
  late final ValueNotifier<List<StrokePoint>> _pointsNotifier;

  @override
  void initState() {
    super.initState();
    _pointsNotifier = ValueNotifier(List.from(widget.points));
  }

  @override
  void didUpdateWidget(DrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync notifier when points change from outside (replay scrubber)
    if (widget.points != oldWidget.points) {
      _pointsNotifier.value = List.from(widget.points);
    }
  }

  @override
  void dispose() {
    _pointsNotifier.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent e) {
    if (widget.readOnly) return;
    final point = StrokePoint(
      x: e.localPosition.dx,
      y: e.localPosition.dy,
      pressure: e.pressure,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isDown: true,
    );
    widget.onPoint(point);
    // Update notifier directly — no setState, no widget tree rebuild
    _pointsNotifier.value = [..._pointsNotifier.value, point];
  }

  void _handlePointerMove(PointerMoveEvent e) {
    if (widget.readOnly) return;
    final point = StrokePoint(
      x: e.localPosition.dx,
      y: e.localPosition.dy,
      pressure: e.pressure,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isDown: true,
    );
    widget.onPoint(point);
    _pointsNotifier.value = [..._pointsNotifier.value, point];
  }

  void _handlePointerUp(PointerUpEvent e) {
    if (widget.readOnly) return;
    final point = StrokePoint(
      x: e.localPosition.dx,
      y: e.localPosition.dy,
      pressure: 0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isDown: false,
    );
    widget.onPoint(point);
    _pointsNotifier.value = [..._pointsNotifier.value, point];
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      child: Container(
        color: Colors.white,
        // RepaintBoundary isolates repaints to just the canvas —
        // the rest of the screen (app bar, banner) never repaints
        child: RepaintBoundary(
          child: ValueListenableBuilder<List<StrokePoint>>(
            valueListenable: _pointsNotifier,
            builder: (context, points, _) {
              return CustomPaint(
                painter: _ClockCanvasPainter(
                  points: points,
                  showCursor: !widget.readOnly,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
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
    if (points.isEmpty) return;

    final strokePaint = Paint()
      ..color = const Color(0xFF1B1464)
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

    // Cursor dot — only when actively drawing, not in replay
    if (showCursor && points.last.isDown) {
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