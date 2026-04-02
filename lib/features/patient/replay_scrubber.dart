import 'package:flutter/material.dart';
import 'package:neuroguard/core/models/stroke_point.dart';
import 'drawing_canvas.dart';

class ReplayScrubber extends StatefulWidget {
  final List<StrokePoint> allPoints;

  const ReplayScrubber({super.key, required this.allPoints});

  @override
  State<ReplayScrubber> createState() => _ReplayScrubberState();
}

class _ReplayScrubberState extends State<ReplayScrubber> {
  double _sliderValue = 1.0;

  List<StrokePoint> get _visiblePoints {
    if (widget.allPoints.isEmpty) return [];
    final count =
    (widget.allPoints.length * _sliderValue).round().clamp(0, widget.allPoints.length);
    return widget.allPoints.sublist(0, count);
  }

  int get _strokeCount {
    return widget.allPoints.where((p) => !p.isDown).length;
  }

  int get _visibleStrokeCount {
    return _visiblePoints.where((p) => !p.isDown).length;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allPoints.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'No drawing data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: [
        // ── Drawing canvas showing replay ─────────────────────────────
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: DrawingCanvas(
              points: _visiblePoints,
              onPoint: (_) {},
              readOnly: true,
            ),
          ),
        ),

        const SizedBox(height: 10),

        // ── Stroke counter ────────────────────────────────────────────
        Text(
          'Stroke $_visibleStrokeCount of $_strokeCount',
          style: const TextStyle(
            color: Color(0xFF7B4FD4),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 4),

        // ── Scrubber ──────────────────────────────────────────────────
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF7B4FD4),
            thumbColor: const Color(0xFF7B4FD4),
            inactiveTrackColor:
            const Color(0xFF7B4FD4).withOpacity(0.2),
            overlayColor: const Color(0xFF7B4FD4).withOpacity(0.1),
            trackHeight: 4,
          ),
          child: Slider(
            value: _sliderValue,
            min: 0.0,
            max: 1.0,
            divisions: widget.allPoints.length.clamp(1, 500),
            onChanged: (val) => setState(() => _sliderValue = val),
          ),
        ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Text('Start',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
            ),
            Text(
              '${(_sliderValue * 100).round()}%',
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Text('End',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
            ),
          ],
        ),

        const SizedBox(height: 4),

        // ── Quick jump buttons ────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _jumpBtn('|◀', 0.0),
            const SizedBox(width: 8),
            _jumpBtn('◀◀', (_sliderValue - 0.1).clamp(0.0, 1.0)),
            const SizedBox(width: 8),
            _jumpBtn('▶▶', (_sliderValue + 0.1).clamp(0.0, 1.0)),
            const SizedBox(width: 8),
            _jumpBtn('▶|', 1.0),
          ],
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  Widget _jumpBtn(String label, double value) => GestureDetector(
    onTap: () => setState(() => _sliderValue = value),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF7B4FD4).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFF7B4FD4).withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Color(0xFF7B4FD4),
            fontSize: 12,
            fontWeight: FontWeight.bold),
      ),
    ),
  );
}