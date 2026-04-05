import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum PocketStatus { onPerson, onTable, unknown }

// ─── Result object returned from every check ─────────────────────────────────
class PocketCheckResult {
  final PocketStatus status;
  final double score;         // 0.0 (definitely on person) → 1.0 (definitely on table)
  final double variance;
  final double peakAmplitude;
  final double decayRate;
  final int sampleCount;

  const PocketCheckResult({
    required this.status,
    required this.score,
    required this.variance,
    required this.peakAmplitude,
    required this.decayRate,
    required this.sampleCount,
  });

  @override
  String toString() =>
      'PocketCheckResult(status: $status, score: ${score.toStringAsFixed(3)}, '
          'variance: ${variance.toStringAsFixed(4)}, peak: ${peakAmplitude.toStringAsFixed(3)}, '
          'decay: ${decayRate.toStringAsFixed(4)}, samples: $sampleCount)';
}

class PocketCheckService {
  static const _platform = MethodChannel('com.neuroguard/pocket_check');

  final String patientId;
  late final DocumentReference _doc;

  // ─── Thresholds (tuned from your real-world test results) ────────────────
  // These are the 3 metrics we now combine into a single weighted score:
  //
  //  1. VARIANCE   — spread of the signal. Hard surface = high variance (vibration
  //                  bounces back). Soft surface / body = low variance (absorbed).
  //
  //  2. PEAK AMP   — max deviation from gravity baseline. Hard surface = high peak.
  //                  Body/pocket = peak is smaller because flesh absorbs energy.
  //
  //  3. DECAY RATE — how fast the vibration energy dies out after the motor stops.
  //                  Hard surface = slow decay (energy keeps reflecting).
  //                  Soft surface = fast decay (energy absorbed quickly).
  //
  // Combined weighted score: 0.0 = definitely ON_PERSON, 1.0 = definitely ON_TABLE

  // Score thresholds — anything above TABLE_THRESHOLD = ON_TABLE
  //                  — anything below PERSON_THRESHOLD = ON_PERSON
  //                  — in between = UNKNOWN (safe default)
  //
  // Dead-zone widened: hard-case phones produce intermediate scores because
  // the case absorbs motor energy, compressing variance and peak toward the
  // body range. A wider UNKNOWN band prevents false ON_PERSON on a table.
  static const double _tableThreshold  = 0.75;   // was 0.72
  static const double _personThreshold = 0.40;   // was 0.55 — widened dead-zone

  // Individual metric bounds (used for 0-1 normalisation)
  //
  // _varianceMin / _peakMin lowered because a hard-case phone on a table
  // produces damped signals (~0.008–0.015 variance, ~0.10–0.20 peak).
  // The old mins were above those values, clamping table readings to 0 and
  // making them indistinguishable from body readings.
  static const double _varianceMin      = 0.005;  // was 0.02
  static const double _varianceMax      = 0.55;
  static const double _peakMin          = 0.08;   // was 0.30
  static const double _peakMax          = 2.20;
  static const double _decayMin         = 0.001;
  static const double _decayMax         = 1.0;

  // Metric weights — MUST sum to 1.0
  // Previous values (0.60 + 0.35 + 0.25 = 1.20) were unnormalised — the raw
  // score could exceed 1.0, making post-inversion scores go negative and
  // rendering both thresholds meaningless.
  // Decay weight reduced to 0.05: the collection window (was 1200 ms) was
  // shorter than the vibration (1600 ms), so there was no post-motor signal
  // to measure — decay was capturing mid-vibration noise, not true decay.
  static const double _wVariance        = 0.65;   // was 0.60
  static const double _wPeak            = 0.30;   // was 0.35
  static const double _wDecay           = 0.05;   // was 0.25 (non-discriminating)

  // Timing
  // _collectDurationMs extended beyond _vibrationDurationMs so the late
  // window of the decay calculation actually captures post-vibration signal.
  // Previously 1200 ms < 1600 ms vibration, so the motor was still running
  // when collection ended — no decay was measurable.
  static const int _vibrationDurationMs       = 1600;
  static const int _preVibrationDelayMs       = 100;
  static const int _collectDurationMs         = 2200;  // was 1200 — now 600 ms post-vibration
  static const int _passiveInactivityMinutes  = 15;
  static const double _passiveVarianceThreshold = 0.008; // stricter for passive check

  Timer? _passiveCheckTimer;
  StreamSubscription<dynamic>? _firebaseCommandListener;

  // Debug mode — prints detailed metrics to console
  final bool debugMode;

  PocketCheckService({required this.patientId, this.debugMode = true}) {
    _doc = FirebaseFirestore.instance.collection('users').doc(patientId);
  }

  // ─── Public API ──────────────────────────────────────────────────────────
  void initialize() {
    _listenForCaregiverCommand();
    _startPassiveInactivityMonitor();
  }

  void dispose() {
    _passiveCheckTimer?.cancel();
    _firebaseCommandListener?.cancel();
  }

  // ─── Listen for caregiver trigger ────────────────────────────────────────
  void _listenForCaregiverCommand() {
    _firebaseCommandListener = _doc.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      final data     = snapshot.data() as Map<String, dynamic>?;
      final commands = data?['commands'] as Map<String, dynamic>?;
      final triggered = commands?['trigger_pocket_check'] as bool? ?? false;

      if (triggered) {
        await _doc.update({'commands.trigger_pocket_check': false});
        await runActiveCheck();
      }
    });
  }

  // ─── ACTIVE CHECK ────────────────────────────────────────────────────────
  Future<PocketCheckResult> runActiveCheck() async {
    await _updateFirestoreStatus('CHECKING');

    // 1. Vibrate
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: _vibrationDurationMs);
    }

    // 2. Short delay for motor spin-up
    await Future.delayed(const Duration(milliseconds: _preVibrationDelayMs));

    // 3. Collect raw 3-axis samples
    final List<_Sample> samples = [];
    final sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.fastestInterval,
    ).listen((AccelerometerEvent e) {
      samples.add(_Sample(e.x, e.y, e.z, DateTime.now()));
    });

    await Future.delayed(const Duration(milliseconds: _collectDurationMs));
    await sub.cancel();

    // 4. Analyse
    final result = _analyse(samples);

    if (debugMode) {
      // ignore: avoid_print
      print('[PocketCheck] score=${result.score.toStringAsFixed(3)} '
          'var=${result.variance.toStringAsFixed(4)} '
          'peak=${result.peakAmplitude.toStringAsFixed(3)} '
          'decay=${result.decayRate.toStringAsFixed(4)}');
    }

    await _reportStatusToFirestore(result.status);
    return result;
  }

  // ─── ANALYSIS ENGINE ─────────────────────────────────────────────────────
  PocketCheckResult _analyse(List<_Sample> samples) {
    if (samples.length < 10) {
      return const PocketCheckResult(
        status: PocketStatus.unknown,
        score: 0.5,
        variance: 0,
        peakAmplitude: 0,
        decayRate: 0,
        sampleCount: 0,
      );
    }

    // ── Gravity-removed magnitude ─────────────────────────────────────────
    // Raw accelerometer always includes ~9.8 m/s² gravity.
    // We remove the gravity component by subtracting the mean of each axis,
    // then compute the total motion magnitude per sample.
    final double meanX = samples.map((s) => s.x).reduce((a, b) => a + b) / samples.length;
    final double meanY = samples.map((s) => s.y).reduce((a, b) => a + b) / samples.length;
    final double meanZ = samples.map((s) => s.z).reduce((a, b) => a + b) / samples.length;

    final List<double> magnitudes = samples.map((s) {
      final dx = s.x - meanX;
      final dy = s.y - meanY;
      final dz = s.z - meanZ;
      return sqrt(dx * dx + dy * dy + dz * dz);
    }).toList();

    // ── Metric 1: Variance ────────────────────────────────────────────────
    final double variance = _variance(magnitudes);

    // ── Metric 2: Peak Amplitude ──────────────────────────────────────────
    // Use 95th percentile instead of absolute max to ignore noise spikes
    final sorted = List<double>.from(magnitudes)..sort();
    final int p95Index = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    final double peakAmplitude = sorted[p95Index];

    // ── Metric 3: Decay Rate ──────────────────────────────────────────────
    // Split signal into early (first 40%) and late (last 40%) windows.
    // Decay = how much the energy drops from the early to the late window.
    // Hard surface: energy stays high (low decay). Body: energy drops fast (high decay).
    final int earlyEnd  = (magnitudes.length * 0.40).floor();
    final int lateStart = (magnitudes.length * 0.60).floor();

    final double earlyMean = magnitudes
        .sublist(0, earlyEnd)
        .reduce((a, b) => a + b) / earlyEnd;
    final double lateMean = magnitudes
        .sublist(lateStart)
        .reduce((a, b) => a + b) / (magnitudes.length - lateStart);

    // FIX: decayRate is now a clean ratio in [0, 1] — the previous code
    // multiplied by 0.06 before storing, then normalised against _decayMax=0.060,
    // causing the value to always saturate at 1.0 and lose its 20 % weight.
    // Now: 0.0 = no decay (hard surface), 1.0 = full decay (body/pocket).
    final double decayRate = earlyMean > 0.001
        ? ((earlyMean - lateMean) / earlyMean).clamp(0.0, 1.0)
        : 0.0;

    // ── Normalise each metric to 0–1 ─────────────────────────────────────
    // 0 = body-like, 1 = hard-surface-like
    final double normVariance = _normalise(variance,    _varianceMin, _varianceMax);
    final double normPeak     = _normalise(peakAmplitude, _peakMin,   _peakMax);
    // Decay is inverted: high decay = on body (low score), low decay = on surface (high score)
    final double normDecay    = 1.0 - _normalise(decayRate, _decayMin, _decayMax);

    // ── Weighted score ────────────────────────────────────────────────────
    final double rawScore = (_wVariance * normVariance)
        + (_wPeak     * normPeak)
        + (_wDecay    * normDecay);
    // INVERT: on this device, higher signal = on person (body adds motion noise)
    // lower signal = on hard surface (motor damps cleanly)
    final double score = 1.0 - rawScore;

    // ── Decision ──────────────────────────────────────────────────────────
    final PocketStatus status;
    if (score >= _tableThreshold) {
      status = PocketStatus.onTable;
    } else if (score <= _personThreshold) {
      status = PocketStatus.onPerson;
    } else {
      status = PocketStatus.unknown;
    }

    return PocketCheckResult(
      status: PocketStatus.values.firstWhere((e) => e == status),
      score: score,
      variance: variance,
      peakAmplitude: peakAmplitude,
      decayRate: decayRate,
      sampleCount: samples.length,
    );
  }

  // ─── PASSIVE CHECK ───────────────────────────────────────────────────────
  void _startPassiveInactivityMonitor() {
    _passiveCheckTimer = Timer.periodic(
      Duration(minutes: _passiveInactivityMinutes),
          (_) async => await _runPassiveCheck(),
    );
  }

  Future<void> _runPassiveCheck() async {
    final List<double> rawMagnitudes = [];

    final sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((AccelerometerEvent e) {
      rawMagnitudes.add(sqrt(e.x * e.x + e.y * e.y + e.z * e.z));
    });

    await Future.delayed(const Duration(seconds: 5));
    await sub.cancel();

    if (rawMagnitudes.isEmpty) return;

    // FIX: subtract the per-sample mean so gravity (~9.8 m/s²) is removed
    // before computing variance. Previously the mean was removed but the
    // resulting detrended list was a list of (value - mean) which is correct;
    // however the original code computed variance on the detrended values
    // which is right — the real issue was that raw magnitudes already include
    // gravity offset, making the mean ≈9.8, and the detrended residuals small.
    // Explicitly document this and ensure we work on detrended values only.
    final double mean = rawMagnitudes.reduce((a, b) => a + b) / rawMagnitudes.length;
    final List<double> detrended = rawMagnitudes.map((v) => v - mean).toList();
    final double variance = _variance(detrended);

    if (debugMode) {
      // ignore: avoid_print
      print('[PocketCheck][Passive] variance=$variance (mean gravity removed: ${mean.toStringAsFixed(3)})');
    }

    if (variance < _passiveVarianceThreshold) {
      await _reportStatusToFirestore(PocketStatus.onTable);
      await _doc.update({
        'alerts.device_abandoned': {
          'timestamp': FieldValue.serverTimestamp(),
          'message': 'Phone may have been left behind — no micro-movement detected',
        },
      });
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────
  double _variance(List<double> data) {
    if (data.isEmpty) return 0.0;
    final mean = data.reduce((a, b) => a + b) / data.length;
    return data.map((v) => pow(v - mean, 2).toDouble()).reduce((a, b) => a + b) / data.length;
  }

  /// Linearly maps [value] from [min..max] to [0..1], clamped.
  double _normalise(double value, double min, double max) {
    if (max <= min) return 0.0;
    return ((value - min) / (max - min)).clamp(0.0, 1.0);
  }

  // ─── Firestore helpers ────────────────────────────────────────────────────
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

  static Future<void> triggerRemoteCheck(String patientId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(patientId)
        .update({'commands.trigger_pocket_check': true});
  }
}

// ─── Internal data class ─────────────────────────────────────────────────────
class _Sample {
  final double x, y, z;
  final DateTime time;
  const _Sample(this.x, this.y, this.z, this.time);
}