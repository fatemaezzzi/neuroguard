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
    final count = (widget.allPoints.length * _sliderValue).round();
    return widget.allPoints.sublist(0, count.clamp(0, widget.allPoints.length));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Drawing shown up to the scrubber position
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

        const SizedBox(height: 12),

        // Scrubber label
        Text(
          'Drag to replay stroke by stroke',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),

        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF7B4FD4),
            thumbColor: const Color(0xFF7B4FD4),
            inactiveTrackColor: const Color(0xFF7B4FD4).withOpacity(0.2),
            overlayColor: const Color(0xFF7B4FD4).withOpacity(0.1),
          ),
          child: Slider(
            value: _sliderValue,
            min: 0.0,
            max: 1.0,
            onChanged: (val) => setState(() => _sliderValue = val),
          ),
        ),

        Text(
          '${(_sliderValue * 100).round()}% of drawing',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}