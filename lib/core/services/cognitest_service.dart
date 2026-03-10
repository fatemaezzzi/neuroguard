import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/stroke_point.dart';

class CogniTestService {
  final _db = FirebaseFirestore.instance;

  // ── TIME-IN-AIR ───────────────────────────────────────────────────────
  double calculateTimeInAir(List<StrokePoint> points) {
    List<double> airTimes = [];
    for (int i = 0; i < points.length - 1; i++) {
      if (!points[i].isDown) {
        for (int j = i + 1; j < points.length; j++) {
          if (points[j].isDown) {
            final airMs = points[j].timestamp - points[i].timestamp;
            final airSeconds = airMs / 1000.0;
            if (airSeconds > 0.05 && airSeconds < 10.0) {
              airTimes.add(airSeconds);
            }
            break;
          }
        }
      }
    }
    if (airTimes.isEmpty) return 0.0;
    return airTimes.reduce((a, b) => a + b) / airTimes.length;
  }

  // ── SCORE ─────────────────────────────────────────────────────────────
  int calculateScore(double avgTimeInAir) {
    if (avgTimeInAir < 0.5) return 95;
    if (avgTimeInAir < 1.0) return 80;
    if (avgTimeInAir < 2.0) return 65;
    if (avgTimeInAir < 3.5) return 45;
    return 25;
  }

  String scoreLabel(int score) {
    if (score >= 80) return 'Great job today! 🌟';
    if (score >= 60) return 'Keep practising 💪';
    return "Let's check in with the doctor 💙";
  }

  // ── SAVE SESSION ──────────────────────────────────────────────────────
  // BUG FIX 2 (slowness): Split into two operations:
  //   1. Save metadata FIRST — this is fast (~200ms) and what we await.
  //   2. Save points array in background — don't block navigation on this.
  //
  // The result screen and history screen only need metadata to display.
  // Points are only needed when the user taps Replay, by which time
  // the background write has long since completed.
  Future<String> saveSession({
    required String patientId,
    required List<StrokePoint> points,
    required double avgTimeInAir,
    required int score,
    bool completed = true,
  }) async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final ref = _db
        .collection('users')
        .doc(patientId)
        .collection('cognitest_sessions')
        .doc(sessionId);

    // Step 1: save metadata only — AWAITED (fast, no points array)
    await ref.set({
      'timestamp': FieldValue.serverTimestamp(),
      'avg_time_in_air': avgTimeInAir,
      'score': score,
      'point_count': points.length,
      'completed': completed,
      // points field intentionally omitted here — written separately below
    });

    // Step 2: save points in background — NOT awaited, does not block nav
    _savePointsInBackground(ref, points);

    return sessionId;
  }

  void _savePointsInBackground(
      DocumentReference ref, List<StrokePoint> points) {
    // Fire and forget — updates the same doc with the points array
    ref.update({
      'points': points.map((p) => p.toMap()).toList(),
    }).catchError((e) {
      // Silently log — points may just not be available for replay
      // if something went wrong, but session metadata is already saved.
      print('Points save failed: $e');
    });
  }

  // ── LOAD SESSIONS ─────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getPastSessions(String patientId) async {
    final snapshot = await _db
        .collection('users')
        .doc(patientId)
        .collection('cognitest_sessions')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['session_id'] = doc.id;
      return data;
    }).toList();
  }

  // ── LOAD POINTS FOR REPLAY ────────────────────────────────────────────
  Future<List<StrokePoint>> getSessionPoints(
      String patientId, String sessionId) async {
    final doc = await _db
        .collection('users')
        .doc(patientId)
        .collection('cognitest_sessions')
        .doc(sessionId)
        .get();

    if (!doc.exists) return [];

    final rawPoints = doc.data()?['points'] as List<dynamic>? ?? [];
    return rawPoints.map((p) {
      final map = p as Map<String, dynamic>;
      return StrokePoint(
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        pressure: (map['pressure'] as num?)?.toDouble() ?? 1.0,
        timestamp: (map['timestamp'] as num).toInt(),
        isDown: map['isDown'] == true,
      );
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────
  // REPORTS PAGE METHODS
  // ─────────────────────────────────────────────────────────────────────

  // ── AVERAGE SCORE over last 30 days ──────────────────────────────────
  Future<double> getAverageScoreLast30Days(String patientId) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final snapshot = await _db
        .collection('users')
        .doc(patientId)
        .collection('cognitest_sessions')
        .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
        .get();

    if (snapshot.docs.isEmpty) return 0.0;

    final scores = snapshot.docs
        .map((d) => (d.data()['score'] as num?)?.toDouble() ?? 0.0)
        .toList();

    return scores.reduce((a, b) => a + b) / scores.length;
  }

  // ── COMPLETION RATE ───────────────────────────────────────────────────
  // Returns a value 0.0–1.0 (e.g. 0.8 = 80% completed)
  Future<double> getCompletionRate(String patientId) async {
    final snapshot = await _db
        .collection('users')
        .doc(patientId)
        .collection('cognitest_sessions')
        .limit(20)
        .get();

    if (snapshot.docs.isEmpty) return 0.0;

    final total = snapshot.docs.length;
    final completed = snapshot.docs
        .where((d) => d.data()['completed'] == true)
        .length;

    return completed / total;
  }

  // ── COGNITIVE DECLINE FLAGS ───────────────────────────────────────────
  // Returns sessions where hover time was significantly above the baseline
  // (baseline = average of all sessions, spike = >50% above baseline)
  Future<List<Map<String, dynamic>>> getDeclineFlags(
      String patientId) async {
    final sessions = await getPastSessions(patientId);
    if (sessions.length < 3) return []; // need at least 3 to detect spikes

    // Calculate baseline average TiA
    final allTia = sessions
        .map((s) => (s['avg_time_in_air'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final baseline = allTia.reduce((a, b) => a + b) / allTia.length;

    // Flag sessions where TiA was >50% above baseline
    return sessions.where((s) {
      final tia = (s['avg_time_in_air'] as num?)?.toDouble() ?? 0.0;
      return tia > baseline * 1.5;
    }).toList();
  }
}