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

  // ─── Thresholds — Recalibrated from 2-session empirical data ─────────────
  //
  // KEY INSIGHT FROM CALIBRATION DATA:
  //
  // The previous model assumed a monotonic relationship:
  //   low variance/peak  →  on person
  //   high variance/peak →  on table
  //
  // Calibration data shows this is WRONG. Observed ranges:
  //
  //   Desk (wood/glass/cloth, both sessions):
  //     variance: 0.18 – 1.19    peak: 1.24 – 2.86    (tight, stable)
  //
  //   Pocket + hard case (Try 1 vs Try 2):
  //     variance: 0.14  →  6.39   peak: 1.21  →  4.68  (highly variable)
  //
  //   Pocket – still (Try 1 vs Try 2):
  //     variance: 0.23  → 13.50   peak: 1.44  →  9.89
  //
  //   Pocket – walking:
  //     variance: 13.68            peak: 7.20
  //
  //   Hand – still (Try 1 vs Try 2):
  //     variance: 0.18  → 12.61   peak: 1.40  → 12.86
  //
  // CONCLUSION: Desk surfaces occupy a TIGHT, LOW variance/peak window.
  // Pocket/body occupies everything ELSE — either similar to desk (when very
  // still) or far above desk range (when moving). The correct model is:
  //
  //   ON_TABLE  = variance AND peak are BOTH within the desk window
  //   ON_PERSON = variance OR peak EXCEEDS the desk ceiling
  //               (body motion pushes at least one metric out of range)
  //
  // For the rare "pocket perfectly still" case where both metrics look desk-
  // like, we rely on the majority-vote across 3 runs — at least one run will
  // capture micro-movements that push a metric out of range.
  //
  // SCORING REDESIGN:
  //   score = how "desk-like" the reading is (0.0 = not desk = on person,
  //                                           1.0 = very desk-like = on table)
  //
  //   We compute a "desk window score" for each metric: 1.0 if the value falls
  //   within the observed desk ceiling, decaying smoothly to 0.0 as it
  //   exceeds the ceiling. Then take the min of both (AND logic — both must be
  //   desk-like to score high).
  //
  // THRESHOLD RATIONALE:
  //   _tableThreshold  = 0.72  → both metrics comfortably inside desk window
  //   _personThreshold = 0.45  → at least one metric well outside desk window
  //   Dead zone 0.45–0.72      → majority vote resolves ambiguity

  static const int    _runsPerCheck         = 2;     // majority-vote runs
  static const int    _interRunDelayMs      = 400;   // gap between runs (motor off)

  static const double _tableThreshold       = 0.65;
  static const double _personThreshold      = 0.40;

  // ── Desk window bounds — derived directly from calibration data ──────────
  //
  // Desk variance ceiling: max observed across all desk readings = 1.19
  //   → set ceiling at 1.50 (adds 26% headroom for sensor variation)
  //   → set floor at 0.05 (below all desk minimums; near-zero = definitely still)
  //
  // Desk peak ceiling: max observed across all desk readings = 2.86
  //   → set ceiling at 3.20 (adds ~12% headroom)
  //   → set floor at 0.80 (below all observed peaks)
  //
  // Values ABOVE the ceiling get a desk-window score < 1.0 that decays toward
  // 0.0 as the value grows. This is computed via a soft gate in _deskWindowScore.
  static const double _varianceDeskFloor   = 0.05;
  static const double _varianceDeskCeiling = 1.80;   // max desk observed: 1.19
  static const double _peakDeskFloor       = 0.80;
  static const double _peakDeskCeiling     = 3.50;   // max desk observed: 2.86

  // Decay is still non-discriminating across conditions (0.43–0.80 everywhere)
  // so it is kept at a negligible weight and not used in desk-window logic.
  static const double _decayMin             = 0.001;
  static const double _decayMax             = 1.0;

  // Metric weights — variance and peak share all weight; decay negligible.
  // We take min(normVariance, normPeak) as the base then blend a small decay
  // component, so the formula is:
  //   score = 0.90 * min(deskVariance, deskPeak) + 0.10 * normDecay
  // The min() encodes the AND requirement — both must be desk-like.
  static const double _wDeskWindow          = 0.90;
  static const double _wDecay               = 0.10;

  // Timing per individual run
  static const int    _vibrationDurationMs  = 1600;
  static const int    _preVibrationDelayMs  = 100;
  static const int    _collectDurationMs    = 2200;  // 600 ms post-vibration for decay window

  static const int    _passiveInactivityMinutes    = 15;
  static const double _passiveVarianceThreshold    = 0.008;

  Timer? _passiveCheckTimer;
  StreamSubscription<dynamic>? _firebaseCommandListener;

  // Last known definitive result — used to avoid writing UNKNOWN when a clear
  // prior reading exists. Reset to null only when the service is disposed.
  PocketStatus? _lastKnownDefinitiveStatus;

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
    _lastKnownDefinitiveStatus = null;
  }

  // ─── Listen for caregiver trigger ────────────────────────────────────────
  void _listenForCaregiverCommand() {
    _firebaseCommandListener = _doc.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      final data      = snapshot.data() as Map<String, dynamic>?;
      final commands  = data?['commands'] as Map<String, dynamic>?;
      final triggered = commands?['trigger_pocket_check'] as bool? ?? false;

      if (triggered) {
        await _doc.update({'commands.trigger_pocket_check': false});
        await runActiveCheck();
      }
    });
  }

  // ─── ACTIVE CHECK (majority-vote across _runsPerCheck runs) ──────────────
  //
  // Each run vibrates, collects samples, and scores them independently.
  // The majority vote across all runs decides the final status.
  //
  // If the majority result is UNKNOWN AND a prior definitive result exists,
  // the Firestore write uses the prior result + a 'uncertain' flag so the
  // caregiver UI can show "Last known: X (uncertain)" instead of bare UNKNOWN.
  Future<PocketCheckResult> runActiveCheck() async {
    await _updateFirestoreStatus('CHECKING');

    final List<PocketCheckResult> runResults = [];

    for (int run = 0; run < _runsPerCheck; run++) {
      // Gap between runs so the motor fully stops before the next vibration.
      // Skip delay before first run.
      if (run > 0) {
        await Future.delayed(const Duration(milliseconds: _interRunDelayMs));
      }

      final result = await _singleRun();
      runResults.add(result);

      if (debugMode) {
        // ignore: avoid_print
        print('[PocketCheck][Run $run] score=${result.score.toStringAsFixed(3)} '
            'var=${result.variance.toStringAsFixed(4)} '
            'peak=${result.peakAmplitude.toStringAsFixed(3)} '
            'decay=${result.decayRate.toStringAsFixed(4)} '
            'status=${result.status.name}');
      }
    }

    // ── Majority vote ─────────────────────────────────────────────────────
    final PocketCheckResult votedResult = _majorityVote(runResults);

    if (debugMode) {
      // ignore: avoid_print
      print('[PocketCheck][Vote] finalStatus=${votedResult.status.name} '
          'avgScore=${votedResult.score.toStringAsFixed(3)}');
    }

    // ── UNKNOWN fallback ──────────────────────────────────────────────────
    // If the voted result is UNKNOWN but we have a prior definitive reading,
    // preserve the prior status and mark it as uncertain so the caregiver
    // sees "Last known: ON_PERSON (uncertain)" instead of just "UNKNOWN".
    if (votedResult.status == PocketStatus.unknown &&
        _lastKnownDefinitiveStatus != null) {
      await _reportStatusToFirestore(
        _lastKnownDefinitiveStatus!,
        uncertain: true,
      );
    } else {
      await _reportStatusToFirestore(votedResult.status, uncertain: false);
      if (votedResult.status != PocketStatus.unknown) {
        _lastKnownDefinitiveStatus = votedResult.status;
      }
    }

    return votedResult;
  }

  // ─── Single vibration run ─────────────────────────────────────────────────
  Future<PocketCheckResult> _singleRun() async {
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

    return _analyse(samples);
  }

  // ─── Majority vote across multiple runs ──────────────────────────────────
  //
  // Returns a synthetic PocketCheckResult whose:
  //   • status = the most common status across all runs
  //   • score  = median of all run scores (more robust than mean vs outliers)
  //   • other metrics = values from the run closest to the median score
  //
  // Tie-breaking (equal votes for ON_PERSON and ON_TABLE): UNKNOWN is returned
  // because the environment is genuinely ambiguous — e.g. phone in loose pocket
  // that sometimes bounces like a hard surface. This should be rare with 3 runs.
  PocketCheckResult _majorityVote(List<PocketCheckResult> results) {
    // Count votes
    int onPersonCount = 0, onTableCount = 0, unknownCount = 0;
    for (final r in results) {
      switch (r.status) {
        case PocketStatus.onPerson: onPersonCount++; break;
        case PocketStatus.onTable:  onTableCount++;  break;
        case PocketStatus.unknown:  unknownCount++;  break;
      }
    }

    final PocketStatus winnerStatus;
    if (onPersonCount > onTableCount && onPersonCount > unknownCount) {
      winnerStatus = PocketStatus.onPerson;
    } else if (onTableCount > onPersonCount && onTableCount > unknownCount) {
      winnerStatus = PocketStatus.onTable;
    } else if (onPersonCount == onTableCount && onPersonCount > 0) {
      // True tie: fall back to the score median to break it
      final scores = results.map((r) => r.score).toList()..sort();
      final medianScore = scores[scores.length ~/ 2];
      winnerStatus = medianScore >= _tableThreshold
          ? PocketStatus.onTable
          : medianScore <= _personThreshold
          ? PocketStatus.onPerson
          : PocketStatus.unknown;
    } else {
      winnerStatus = PocketStatus.unknown;
    }

    // Use median score and the representative run's raw metrics
    final scores = results.map((r) => r.score).toList()..sort();
    final double medianScore = scores[scores.length ~/ 2];

    // Pick the run whose score is closest to the median for representative metrics
    final rep = results.reduce((a, b) =>
    (a.score - medianScore).abs() < (b.score - medianScore).abs() ? a : b);

    return PocketCheckResult(
      status:        winnerStatus,
      score:         medianScore,
      variance:      rep.variance,
      peakAmplitude: rep.peakAmplitude,
      decayRate:     rep.decayRate,
      sampleCount:   rep.sampleCount,
    );
  }

  // ─── ANALYSIS ENGINE ─────────────────────────────────────────────────────
  //
  // SCORING MODEL CHANGE — "desk window" approach:
  //
  // Old model: normalise variance/peak linearly from min→max, high = table.
  //   Problem: pocket sometimes produces variance of 13.5 and peak of 9.9,
  //   which clipped to 1.0 in the old linear normalisation and was scored as
  //   ON_TABLE — exactly backwards.
  //
  // New model: score = how closely the reading resembles the DESK window.
  //   Each metric is given a "desk window score":
  //     • 1.0 if value ≤ desk ceiling (comfortably desk-like)
  //     • smoothly decays toward 0.0 as value exceeds the ceiling
  //   Final score = 0.90 * min(deskVariance, deskPeak) + 0.10 * normDecay
  //   The min() encodes: BOTH metrics must be desk-like to score high.
  //   If either is elevated (body motion), the score drops → ON_PERSON.
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

    // ── Metric 2: Peak Amplitude (95th percentile) ────────────────────────
    final sorted = List<double>.from(magnitudes)..sort();
    final int p95Index = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    final double peakAmplitude = sorted[p95Index];

    // ── Metric 3: Decay Rate ──────────────────────────────────────────────
    final int earlyEnd  = (magnitudes.length * 0.40).floor();
    final int lateStart = (magnitudes.length * 0.60).floor();

    final double earlyMean = magnitudes
        .sublist(0, earlyEnd)
        .reduce((a, b) => a + b) / earlyEnd;
    final double lateMean = magnitudes
        .sublist(lateStart)
        .reduce((a, b) => a + b) / (magnitudes.length - lateStart);

    final double decayRate = earlyMean > 0.001
        ? ((earlyMean - lateMean) / earlyMean).clamp(0.0, 1.0)
        : 0.0;

    // ── Desk-window scores ────────────────────────────────────────────────
    // _deskWindowScore returns 1.0 when value ≤ ceiling, then decays smoothly.
    // Decay: high decay on a hard surface means vibration dissipated quickly
    // (energy reflected, not absorbed). Invert for desk-likeness:
    //   normDecay = 1 - normalised(decayRate) → high decay = low desk score.
    // (Decay has minimal discriminating power so weight is small anyway.)
    final double deskVarianceScore = _deskWindowScore(
        variance, _varianceDeskFloor, _varianceDeskCeiling);
    final double deskPeakScore     = _deskWindowScore(
        peakAmplitude, _peakDeskFloor, _peakDeskCeiling);
    final double normDecay         = 1.0 - _normalise(decayRate, _decayMin, _decayMax);

    // AND logic via min(): both metrics must be desk-like to score high.
    final double deskWindowScore = min(deskVarianceScore, deskPeakScore);

    final double score = (_wDeskWindow * deskWindowScore) + (_wDecay * normDecay);

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
      status:        status,
      score:         score,
      variance:      variance,
      peakAmplitude: peakAmplitude,
      decayRate:     decayRate,
      sampleCount:   samples.length,
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

    final double mean = rawMagnitudes.reduce((a, b) => a + b) / rawMagnitudes.length;
    final List<double> detrended = rawMagnitudes.map((v) => v - mean).toList();
    final double variance = _variance(detrended);

    if (debugMode) {
      // ignore: avoid_print
      print('[PocketCheck][Passive] variance=$variance (gravity mean: ${mean.toStringAsFixed(3)})');
    }

    if (variance < _passiveVarianceThreshold) {
      await _reportStatusToFirestore(PocketStatus.onTable, uncertain: false);
      _lastKnownDefinitiveStatus = PocketStatus.onTable;
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

  double _normalise(double value, double min, double max) {
    if (max <= min) return 0.0;
    return ((value - min) / (max - min)).clamp(0.0, 1.0);
  }

  // Desk-window score: 1.0 when value is within [floor, ceiling].
  // Above the ceiling, score decays as 1 / (1 + k * overshoot), where
  // overshoot = (value - ceiling) / ceiling. k=4 gives a smooth but fairly
  // rapid decay — doubling the ceiling value brings the score to ~0.2.
  // Below the floor, score also decays (very still = potentially on person too,
  // but this is resolved by the majority-vote rather than a hard 0).
  double _deskWindowScore(double value, double floor, double ceiling) {
    if (value <= ceiling && value >= floor) {
      return 1.0;
    } else if (value > ceiling) {
      final double overshoot = (value - ceiling) / ceiling;
      return 1.0 / (1.0 + 4.0 * overshoot);
    } else {
      // Below floor — scale from 0 at 0 to 1 at floor
      return (value / floor).clamp(0.0, 1.0);
    }
  }

  // ─── Firestore helpers ────────────────────────────────────────────────────
  Future<void> _updateFirestoreStatus(String status) async {
    await _doc.update({'sensors.pocket_status': status});
  }

  // uncertain=true means: we use the last known status but flag it so the
  // caregiver UI can show a visual indicator like "(uncertain)" or a muted dot.
  Future<void> _reportStatusToFirestore(
      PocketStatus status, {
        bool uncertain = false,
      }) async {
    final statusStr = switch (status) {
      PocketStatus.onPerson => 'ON_PERSON',
      PocketStatus.onTable  => 'ON_TABLE',
      PocketStatus.unknown  => 'UNKNOWN',
    };
    await _doc.update({
      'sensors.pocket_status':            statusStr,
      'sensors.pocket_check_timestamp':   FieldValue.serverTimestamp(),
      // New field: caregiver UI reads this to show "(uncertain)" indicator
      // when the vote was ambiguous but we fell back to last known status.
      'sensors.pocket_status_uncertain':  uncertain,
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