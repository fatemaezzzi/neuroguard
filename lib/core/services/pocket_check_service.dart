import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum PocketStatus { onPerson, onTable, unknown }

class PocketCheckService {
  static const _platform = MethodChannel('com.neuroguard/pocket_check');

  final String patientId;
  late final DocumentReference _doc;

  // Tuning constants — adjust based on real-world testing
  static const double _dampedVarianceThreshold = 0.08;
  static const double _hardSurfaceVarianceThreshold = 0.35;
  static const int _vibrationDurationMs = 600;
  static const int _listenDurationMs = 1200;
  static const int _passiveInactivityMinutes = 15;

  Timer? _passiveCheckTimer;
  StreamSubscription? _firebaseCommandListener;

  PocketCheckService({required this.patientId}) {
    _doc = FirebaseFirestore.instance
        .collection('users')
        .doc(patientId);
  }

  // ─── Start the service ───────────────────────────────────────────────
  void initialize() {
    _listenForCaregiverCommand();
    _startPassiveInactivityMonitor();
  }

  void dispose() {
    _passiveCheckTimer?.cancel();
    _firebaseCommandListener?.cancel();
  }

  // ─── Listen for caregiver-triggered pocket check ─────────────────────
  void _listenForCaregiverCommand() {
    _firebaseCommandListener = _doc.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>?;
      final commands = data?['commands'] as Map<String, dynamic>?;
      final triggered = commands?['trigger_pocket_check'] as bool? ?? false;

      if (triggered) {
        // Reset the flag immediately to prevent re-triggering
        await _doc.update({'commands.trigger_pocket_check': false});
        await runActiveCheck();
      }
    });
  }

  // ─── ACTIVE CHECK: Vibrate & Listen ──────────────────────────────────
  // Vibrates the phone, then samples the accelerometer to measure
  // how much the vibration was dampened by the surrounding surface.
  Future<PocketStatus> runActiveCheck() async {
    await _updateFirestoreStatus('CHECKING');

    // Step 1: Trigger vibration
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: _vibrationDurationMs);
    }

    // Step 2: Wait 100ms for vibration to start, then sample
    await Future.delayed(const Duration(milliseconds: 100));
    final List<double> zAxisSamples = [];

    final subscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.fastestInterval,
    ).listen((AccelerometerEvent event) {
      zAxisSamples.add(event.z);
    });

    // Step 3: Collect samples for the listen duration
    await Future.delayed(Duration(milliseconds: _listenDurationMs));
    await subscription.cancel();

    // Step 4: Analyze the variance of collected samples
    final status = _analyzeVariance(zAxisSamples);
    await _reportStatusToFirestore(status);
    return status;
  }

  // ─── PASSIVE CHECK: Absolute stillness detection ─────────────────────
  // A human body always has micro-movements (breathing, shifting).
  // If the phone is perfectly still for 15 minutes, it's been left behind.
  void _startPassiveInactivityMonitor() {
    _passiveCheckTimer = Timer.periodic(
      Duration(minutes: _passiveInactivityMinutes),
          (_) async => await _runPassiveCheck(),
    );
  }

  Future<void> _runPassiveCheck() async {
    final List<double> samples = [];

    final sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((e) {
      samples.add(sqrt(e.x * e.x + e.y * e.y + e.z * e.z));
    });

    // Sample for 5 seconds
    await Future.delayed(const Duration(seconds: 5));
    await sub.cancel();

    if (samples.isEmpty) return;

    final variance = _calculateVariance(samples);

    // Near-zero variance = phone sitting perfectly still on a surface
    if (variance < 0.01) {
      await _reportStatusToFirestore(PocketStatus.onTable);

      // Push a "device abandoned" alert into Firestore
      await _doc.update({
        'alerts.device_abandoned': {
          'timestamp': FieldValue.serverTimestamp(),
          'message': 'Phone may have been left behind — no micro-movement detected',
        },
      });
    }
  }

  // ─── Variance Analysis ────────────────────────────────────────────────
  PocketStatus _analyzeVariance(List<double> samples) {
    if (samples.length < 5) return PocketStatus.unknown;

    final variance = _calculateVariance(samples);

    if (variance > _hardSurfaceVarianceThreshold) {
      return PocketStatus.onTable;
    } else if (variance < _dampedVarianceThreshold) {
      return PocketStatus.onPerson;
    }
    return PocketStatus.unknown;
  }

  double _calculateVariance(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    final squaredDiffs = samples.map((v) => pow(v - mean, 2).toDouble());
    return squaredDiffs.reduce((a, b) => a + b) / samples.length;
  }

  // ─── Firestore Status Reporting ───────────────────────────────────────
  Future<void> _updateFirestoreStatus(String status) async {
    await _doc.update({'sensors.pocket_status': status});
  }

  Future<void> _reportStatusToFirestore(PocketStatus status) async {
    final statusStr = switch (status) {
      PocketStatus.onPerson => 'ON_PERSON',
      PocketStatus.onTable  => 'ON_TABLE',
      PocketStatus.unknown  => 'UNKNOWN',
    };
    await _doc.update({
      'sensors.pocket_status': statusStr,
      'sensors.pocket_check_timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ─── Caregiver-side: trigger a check remotely ─────────────────────────
  static Future<void> triggerRemoteCheck(String patientId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(patientId)
        .update({'commands.trigger_pocket_check': true});
  }
}