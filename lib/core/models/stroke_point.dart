class StrokePoint {
  final double x;
  final double y;
  final double pressure;
  final int timestamp; // milliseconds since epoch
  final bool isDown;   // true = finger on screen, false = finger lifted

  StrokePoint({
    required this.x,
    required this.y,
    required this.pressure,
    required this.timestamp,
    required this.isDown,
  });

  Map<String, dynamic> toMap() => {
    'x': x,
    'y': y,
    'pressure': pressure,
    'timestamp': timestamp,
    'isDown': isDown,
  };

  factory StrokePoint.fromMap(Map<String, dynamic> map) => StrokePoint(
    x: (map['x'] as num).toDouble(),
    y: (map['y'] as num).toDouble(),
    pressure: (map['pressure'] as num).toDouble(),
    timestamp: map['timestamp'] as int,
    isDown: map['isDown'] as bool,
  );
}