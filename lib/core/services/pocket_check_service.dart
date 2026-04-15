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
  final double score;           // 0.0 (on person) → 1.0 (on table)
  final double variance;
  final double peakAmplitude;
  final double decayRate;       // kept for logging; no longer used in scoring
  final double oscillationIndex; // NEW: underdamped body signature
  final double varToPeakRatio;   // NEW: low ratio = body-still
  final int sampleCount;

  const PocketCheckResult({
    required this.status,
    required this.score,
    required this.variance,
    required this.peakAmplitude,
    required this.decayRate,
    required this.oscillationIndex,
    required this.varToPeakRatio,
    required this.sampleCount,
  });

  @override
  String toString() =>
      'PocketCheckResult(status: $status, score: ${score.toStringAsFixed(3)}, '
          'variance: ${variance.toStringAsFixed(4)}, peak: ${peakAmplitude.toStringAsFixed(3)}, '
          'decay: ${decayRate.toStringAsFixed(4)}, '
          'oscillation: ${oscillationIndex.toStringAsFixed(3)}, '
          'varPeakRatio: ${varToPeakRatio.toStringAsFixed(4)}, '
          'samples: $sampleCount)';
}

class PocketCheckService {
  static const _platform = MethodChannel('com.neuroguard/pocket_check');

  final String patientId;
  late final DocumentReference _doc;

  // ─── Thresholds ─────────────────────────────────────────────────────────────
  //
  // SCORING MODEL v3 — "desk window + body signature" approach
  //
  // Three evidence sources are combined:
  //
  //  1. DESK WINDOW SCORE  (variance & peak)
  //     Hard surfaces produce tight, bounded variance/peak.
  //     Score = 1.0 when both metrics fall within the observed desk window,
  //     decaying toward 0.0 as either metric exceeds the ceiling.
  //     Weight: 0.60 (was 0.90 — reduced to make room for new features)
  //
  //  2. OSCILLATION INDEX  (post-peak zero-crossing count)
  //     Research basis: soft tissue vibrates as an *under-damped* system
  //     (Wakeling & Nigg, J Appl Physiol 2001; 2002). After a vibration
  //     impulse, body contact produces residual oscillation in the signal
  //     before it settles, whereas a hard surface damps monotonically.
  //     High oscillation  →  score contribution LOW  →  ON_PERSON
  //     Low oscillation   →  score contribution HIGH →  ON_TABLE
  //     Weight: 0.25
  //
  //  3. VARIANCE-TO-PEAK RATIO
  //     Research basis: VibePhone (Cho, Hwang & Oh, Pattern Anal Appl 2016)
  //     demonstrates that no single metric separates body from table — a
  //     combination of features is required. Body-still contact suppresses
  //     variance (soft tissue absorbs micro-energy) but the initial vibration
  //     peak still reaches the accelerometer, producing an anomalously LOW
  //     variance/peak ratio. Hard surfaces show a proportional relationship.
  //     Low ratio  →  score contribution LOW  →  ON_PERSON
  //     Mid ratio  →  score contribution HIGH →  ON_TABLE
  //     Weight: 0.15
  //
  // THRESHOLD CHANGES:
  //   _tableThreshold  = 0.65  (unchanged)
  //   _personThreshold = 0.35  (was 0.50)
  //     ↳ Justification: oscillation index now depresses body scores reliably,
  //       so the dead zone can be narrowed without increasing false positives.
  //       Body-still readings that previously hovered at 0.50–0.55 (due to
  //       desk-like variance/peak) will now score ≤ 0.40 once the oscillation
  //       and varToPeak penalty is applied.

  static const int    _runsPerCheck        = 3;
  static const int    _interRunDelayMs     = 400;

  static const double _tableThreshold      = 0.65;
  static const double _personThreshold     = 0.35; // lowered from 0.50

  // ── Desk window bounds (from empirical calibration data) ──────────────────
  static const double _varianceDeskFloor   = 0.05;
  static const double _varianceDeskCeiling = 1.80;
  static const double _peakDeskFloor       = 0.80;
  static const double _peakDeskCeiling     = 3.50;

  // ── Metric weights ────────────────────────────────────────────────────────
  // Desk window  : 0.60   (was 0.90 — variance+peak share this via min())
  // Oscillation  : 0.25   (NEW — underdamped body signature)
  // VarPeak ratio: 0.15   (NEW — body-still discriminator)
  static const double _wDeskWindow     = 0.60;
  static const double _wOscillation    = 0.25;
  static const double _wVarPeakRatio   = 0.15;

  // Oscillation index tuning:
  //   Zero-crossings of (signal − rollingMean) in the post-peak window.
  //   Empirically, body contact produces 4–10 crossings; hard surfaces 0–2.
  //   _oscillationSaturation = crossings at which index is clamped to 1.0.
  //   Score contribution = 1.0 - oscillationIndex (high crossings = body).
  static const double _oscillationSaturation = 8.0;

  // VarPeakRatio tuning:
  //   On-table: ratio ≈ 0.10–0.60 (variance and peak scale together)
  //   On-body-still: ratio < 0.08 (soft tissue damps variance but not peak)
  //   Score is 0.0 when ratio < _ratioBodyMax, rising to 1.0 at _ratioTableMin.
  static const double _ratioBodyMax    = 0.08;  // below = body-like
  static const double _ratioTableMin   = 0.18;  // above = table-like

  // Timing
  static const int    _vibrationDurationMs = 1600;
  static const int    _preVibrationDelayMs = 100;
  static const int    _collectDurationMs   = 2200;

  static const int    _passiveInactivityMinutes  = 15;
  static const double _passiveVarianceThreshold  = 0.008;

  Timer? _passiveCheckTimer;
  StreamSubscription<dynamic>? _firebaseCommandListener;

  bool _isCheckInProgress = false;
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
    _isCheckInProgress = false;
  }

  // ─── Listen for caregiver trigger ────────────────────────────────────────
  void _listenForCaregiverCommand() {
    _firebaseCommandListener = _doc.snapshots().listen((snapshot) async {
      if (!snapshot.exists || _isCheckInProgress) return;

      final data      = snapshot.data() as Map<String, dynamic>?;
      final commands  = data?['commands'] as Map<String, dynamic>?;
      final triggered = commands?['trigger_pocket_check'] as bool? ?? false;

      if (triggered) {
        _isCheckInProgress = true;
        await _doc.update({'commands.trigger_pocket_check': false});
        await runActiveCheck();
        _isCheckInProgress = false;
      }
    });
  }

  // ─── ACTIVE CHECK (majority-vote across _runsPerCheck runs) ──────────────
  Future<PocketCheckResult> runActiveCheck() async {
    await _updateFirestoreStatus('CHECKING');

    final List<PocketCheckResult> runResults = [];

    for (int run = 0; run < _runsPerCheck; run++) {
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
            'osc=${result.oscillationIndex.toStringAsFixed(3)} '
            'vpr=${result.varToPeakRatio.toStringAsFixed(4)} '
            'status=${result.status.name}');
      }
    }

    final PocketCheckResult votedResult = _majorityVote(runResults);

    if (debugMode) {
      // ignore: avoid_print
      print('[PocketCheck][Vote] finalStatus=${votedResult.status.name} '
          'avgScore=${votedResult.score.toStringAsFixed(3)}');
    }

    if (votedResult.status == PocketStatus.unknown &&
        _lastKnownDefinitiveStatus != null) {
      await _reportStatusToFirestore(
        _lastKnownDefinitiveStatus!,
        uncertain: true,
        result: votedResult,
      );
    } else {
      await _reportStatusToFirestore(
        votedResult.status,
        uncertain: false,
        result: votedResult,
      );
      if (votedResult.status != PocketStatus.unknown) {
        _lastKnownDefinitiveStatus = votedResult.status;
      }
    }

    return votedResult;
  }

  // ─── Single vibration run ─────────────────────────────────────────────────
  Future<PocketCheckResult> _singleRun() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: _vibrationDurationMs);
    }

    await Future.delayed(const Duration(milliseconds: _preVibrationDelayMs));

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
  PocketCheckResult _majorityVote(List<PocketCheckResult> results) {
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

    final scores = results.map((r) => r.score).toList()..sort();
    final double medianScore = scores[scores.length ~/ 2];

    final rep = results.reduce((a, b) =>
    (a.score - medianScore).abs() < (b.score - medianScore).abs() ? a : b);

    return PocketCheckResult(
      status:           winnerStatus,
      score:            medianScore,
      variance:         rep.variance,
      peakAmplitude:    rep.peakAmplitude,
      decayRate:        rep.decayRate,
      oscillationIndex: rep.oscillationIndex,
      varToPeakRatio:   rep.varToPeakRatio,
      sampleCount:      rep.sampleCount,
    );
  }

  // ─── ANALYSIS ENGINE ──────────────────────────────────────────────────────
  //
  // SCORING MODEL v3:
  //   score = 0.60 * min(deskVarianceScore, deskPeakScore)   [AND desk logic]
  //         + 0.25 * (1.0 - oscillationIndex)                [body = oscillates]
  //         + 0.15 * varToPeakRatioScore                     [body-still = low ratio]
  //
  // A high score means "desk-like". A low score means "body-like".
  //
  // RESEARCH BASIS:
  //   • VibePhone (Cho et al., PAA 2016): combined features required for
  //     body/table separation; single metrics are insufficient.
  //   • Wakeling & Nigg (J Appl Physiol 2001; 2002): soft tissue produces
  //     under-damped, oscillatory vibration response — hard surfaces do not.
  //   • Frequency-dependent tissue absorption (PMC 4694567): soft tissue
  //     absorbs high-frequency components locally, reducing variance while
  //     the initial peak (lower frequency) still propagates — explaining
  //     the anomalously low var/peak ratio on body-still contact.
  PocketCheckResult _analyse(List<_Sample> samples) {
    if (samples.length < 10) {
      return const PocketCheckResult(
        status:           PocketStatus.unknown,
        score:            0.5,
        variance:         0,
        peakAmplitude:    0,
        decayRate:        0,
        oscillationIndex: 0,
        varToPeakRatio:   0,
        sampleCount:      0,
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

    // ── Metric 3: Decay Rate (kept for logging only; not scored) ──────────
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

    // ── Metric 4: Oscillation Index (NEW) ────────────────────────────────
    // Counts zero-crossings of (magnitude − rolling mean) in the post-peak
    // window. Soft tissue vibrates as an under-damped system (Wakeling &
    // Nigg 2001), producing residual oscillation after the impulse peak.
    // Hard surfaces exhibit monotonic, over-damped decay with few crossings.
    // High crossing count → high oscillationIndex → low score → ON_PERSON.
    final double oscillationIndex = _computeOscillationIndex(magnitudes);

    // ── Metric 5: Variance-to-Peak Ratio (NEW) ────────────────────────────
    // Soft tissue selectively absorbs high-frequency components of vibration
    // (resonant frequency of fingers: 150–300 Hz, per PMC 4694567), which
    // suppresses variance while the lower-frequency initial peak still
    // propagates. This gives body-still an anomalously low var/peak ratio.
    final double varToPeakRatio = (peakAmplitude > 0.01)
        ? (variance / peakAmplitude).clamp(0.0, 2.0)
        : 0.0;

    // ── Desk-window scores ────────────────────────────────────────────────
    final double deskVarianceScore = _deskWindowScore(
        variance, _varianceDeskFloor, _varianceDeskCeiling);
    final double deskPeakScore     = _deskWindowScore(
        peakAmplitude, _peakDeskFloor, _peakDeskCeiling);

    // AND logic: both must be desk-like to score high
    final double deskWindowScore = min(deskVarianceScore, deskPeakScore);

    // Oscillation score: invert — high oscillation = body = low desk score
    // Normalise crossings against saturation point, then invert.
    final double oscillationScore = 1.0 - oscillationIndex;

    // VarPeak ratio score: ramp from 0.0 (body-like) to 1.0 (table-like)
    //   ratio < _ratioBodyMax  → score 0.0 (definitely body)
    //   ratio > _ratioTableMin → score 1.0 (table-like)
    final double varPeakScore = _normalise(
        varToPeakRatio, _ratioBodyMax, _ratioTableMin);

    // ── Final composite score ─────────────────────────────────────────────
    final double score =
        (_wDeskWindow   * deskWindowScore) +
            (_wOscillation  * oscillationScore) +
            (_wVarPeakRatio * varPeakScore);

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
      status:           status,
      score:            score,
      variance:         variance,
      peakAmplitude:    peakAmplitude,
      decayRate:        decayRate,
      oscillationIndex: oscillationIndex,
      varToPeakRatio:   varToPeakRatio,
      sampleCount:      samples.length,
    );
  }

  // ─── Oscillation Index Computation ───────────────────────────────────────
  //
  // 1. Find the peak sample index.
  // 2. Work on the post-peak window only (where decay / oscillation occurs).
  // 3. Compute a short rolling mean (window = 5 samples) to establish a
  //    local baseline, then count sign changes of (sample − baseline).
  // 4. Normalise against _oscillationSaturation and clamp to [0,1].
  //
  // A body contact reading typically yields 4–10 crossings.
  // A hard surface typically yields 0–2 crossings.
  double _computeOscillationIndex(List<double> magnitudes) {
    if (magnitudes.length < 20) return 0.0;

    // Find peak index
    int peakIdx = 0;
    double peakVal = 0.0;
    for (int i = 0; i < magnitudes.length; i++) {
      if (magnitudes[i] > peakVal) {
        peakVal = magnitudes[i];
        peakIdx = i;
      }
    }

    // Post-peak window — need at least 10 samples to be meaningful
    if (peakIdx >= magnitudes.length - 10) return 0.0;
    final postPeak = magnitudes.sublist(peakIdx);

    // Rolling mean with window size 5
    const int windowSize = 5;
    int crossings = 0;
    double? prevDiff;

    for (int i = windowSize; i < postPeak.length; i++) {
      double windowMean = 0.0;
      for (int j = i - windowSize; j < i; j++) {
        windowMean += postPeak[j];
      }
      windowMean /= windowSize;

      final double diff = postPeak[i] - windowMean;
      if (prevDiff != null && prevDiff! * diff < 0) {
        crossings++;
      }
      prevDiff = diff;
    }

    return (crossings / _oscillationSaturation).clamp(0.0, 1.0);
  }

  // ─── PASSIVE CHECK ───────────────────────────────────────────────────────
  void _startPassiveInactivityMonitor() {
    _passiveCheckTimer = Timer.periodic(
      Duration(minutes: _passiveInactivityMinutes),
          (_) async => await _runPassiveCheck(),
    );
  }

  Future<void> _runPassiveCheck() async {
    final List<AccelerometerEvent> events = [];

    final sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((AccelerometerEvent e) => events.add(e));

    await Future.delayed(const Duration(seconds: 5));
    await sub.cancel();

    if (events.isEmpty) return;

    // Remove gravity per-axis, then compute magnitude — mirrors _analyse()
    final double meanX = events.map((e) => e.x).reduce((a, b) => a + b) / events.length;
    final double meanY = events.map((e) => e.y).reduce((a, b) => a + b) / events.length;
    final double meanZ = events.map((e) => e.z).reduce((a, b) => a + b) / events.length;

    final List<double> magnitudes = events.map((e) {
      final dx = e.x - meanX;
      final dy = e.y - meanY;
      final dz = e.z - meanZ;
      return sqrt(dx * dx + dy * dy + dz * dz);
    }).toList();

    final double variance = _variance(magnitudes);

    if (debugMode) {
      // ignore: avoid_print
      print('[PocketCheck][Passive] variance=$variance (gravity removed; '
          'meanX=${meanX.toStringAsFixed(3)} meanY=${meanY.toStringAsFixed(3)} '
          'meanZ=${meanZ.toStringAsFixed(3)})');
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
  // Above the ceiling, score decays as 1 / (1 + k * overshoot).
  // k=4 gives rapid but smooth decay — doubling the ceiling → score ~0.2.
  // Below the floor, score scales linearly from 0 (at 0) to 1 (at floor).
  double _deskWindowScore(double value, double floor, double ceiling) {
    if (value <= ceiling && value >= floor) {
      return 1.0;
    } else if (value > ceiling) {
      final double overshoot = (value - ceiling) / ceiling;
      return 1.0 / (1.0 + 4.0 * overshoot);
    } else {
      return (value / floor).clamp(0.0, 1.0);
    }
  }

  // ─── Firestore helpers ────────────────────────────────────────────────────
  Future<void> _updateFirestoreStatus(String status) async {
    await _doc.update({
      'sensors.pocket_status':           status,
      'sensors.pocket_status_uncertain': false,
    });
  }

  Future<void> _reportStatusToFirestore(
      PocketStatus status, {
        bool uncertain = false,
        PocketCheckResult? result,
      }) async {
    final statusStr = switch (status) {
      PocketStatus.onPerson => 'ON_PERSON',
      PocketStatus.onTable  => 'ON_TABLE',
      PocketStatus.unknown  => 'UNKNOWN',
    };
    await _doc.update({
      'sensors.pocket_status':            statusStr,
      'sensors.pocket_check_timestamp':   FieldValue.serverTimestamp(),
      'sensors.pocket_status_uncertain':  uncertain,
      // Diagnostic fields — read by PocketCheckCard when showDiagnostics=true
      if (result != null) ...{
        'sensors.pocket_last_score':        result.score,
        'sensors.pocket_oscillation_index': result.oscillationIndex,
        'sensors.pocket_var_peak_ratio':    result.varToPeakRatio,
      },
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