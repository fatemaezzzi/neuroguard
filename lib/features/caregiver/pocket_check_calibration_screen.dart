import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

// ─────────────────────────────────────────────────────────────────────────────
// POCKET CHECK CALIBRATION SCREEN
//
// PURPOSE: Collect raw sensor readings across different surfaces and positions
// so you can see exactly what variance / peak / decayRate your specific phone
// produces before touching any threshold values.
//
// HOW TO USE:
//   1. Add this screen to your app temporarily (add a route or push it directly)
//   2. Place phone in each scenario and tap the matching button
//   3. Read the raw numbers printed in the log panel on screen
//   4. Note the variance / peak / decay ranges for each scenario
//   5. Use those real ranges to set thresholds in pocket_check_service.dart
//
// SCENARIOS TO TEST (do each 3–4 times for reliable ranges):
//   • Flat on wooden desk
//   • Flat on glass/marble table
//   • Flat on soft surface (cloth, bed)
//   • In jeans pocket (standing still)
//   • In jeans pocket (walking a few steps)
//   • Held in hand (still)
//   • Flat on desk WITH hard phone case
//   • In pocket WITH hard phone case
// ─────────────────────────────────────────────────────────────────────────────

class PocketCheckCalibrationScreen extends StatefulWidget {
  const PocketCheckCalibrationScreen({super.key});

  @override
  State<PocketCheckCalibrationScreen> createState() =>
      _PocketCheckCalibrationScreenState();
}

class _PocketCheckCalibrationScreenState
    extends State<PocketCheckCalibrationScreen> {

  // ── Config ─────────────────────────────────────────────────────────────────
  static const int    _vibrationDurationMs = 1600;
  static const int    _preVibrationDelayMs = 100;
  static const int    _collectDurationMs   = 2200;

  // ── State ──────────────────────────────────────────────────────────────────
  bool   _isRunning  = false;
  String _activeLabel = '';

  // Each entry: { label, variance, peak, decay, score, sampleCount }
  final List<Map<String, dynamic>> _readings = [];

  // Scrolls the log to the bottom after each new reading
  final ScrollController _scrollController = ScrollController();

  // ── Scenarios ──────────────────────────────────────────────────────────────
  // Add / remove rows here to match what you want to test.
  // colour is just for visual grouping in the UI.
  static const List<_Scenario> _scenarios = [
    _Scenario('Desk (wood)',       Color(0xFF795548), Icons.desk),
    _Scenario('Desk (glass)',      Color(0xFF607D8B), Icons.desk),
    _Scenario('Desk (cloth)',      Color(0xFF9C27B0), Icons.table_restaurant),
    _Scenario('Pocket – still',   Color(0xFF1976D2), Icons.rocket_sharp),
    _Scenario('Pocket – walking', Color(0xFF0288D1), Icons.directions_walk),
    _Scenario('Hand – still',     Color(0xFF388E3C), Icons.back_hand),
    _Scenario('Desk + hard case', Color(0xFFE64A19), Icons.phone_android),
    _Scenario('Pocket + hard case',Color(0xFFD32F2F), Icons.rocket_sharp),
  ];

  // ── Run a single calibration check ─────────────────────────────────────────
  Future<void> _runCheck(String label) async {
    if (_isRunning) return;
    setState(() {
      _isRunning    = true;
      _activeLabel  = label;
    });

    // 1. Vibrate
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: _vibrationDurationMs);
    }

    // 2. Spin-up delay
    await Future.delayed(const Duration(milliseconds: _preVibrationDelayMs));

    // 3. Collect
    final List<_RawSample> samples = [];
    final sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.fastestInterval,
    ).listen((AccelerometerEvent e) {
      samples.add(_RawSample(e.x, e.y, e.z, DateTime.now()));
    });

    await Future.delayed(const Duration(milliseconds: _collectDurationMs));
    await sub.cancel();

    // 4. Analyse
    final result = _analyse(samples, label);

    setState(() {
      _readings.add(result);
      _isRunning   = false;
      _activeLabel = '';
    });

    // Scroll log to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Analysis (mirrors pocket_check_service._analyse exactly) ───────────────
  // Returns a plain map so you see exactly the numbers the service would use.
  Map<String, dynamic> _analyse(List<_RawSample> samples, String label) {
    if (samples.length < 10) {
      return {
        'label': label,
        'error': 'Too few samples (${samples.length})',
        'variance': 0.0,
        'peak': 0.0,
        'decay': 0.0,
        'samples': samples.length,
      };
    }

    // Gravity-removed magnitude
    final double meanX = samples.map((s) => s.x).reduce((a, b) => a + b) / samples.length;
    final double meanY = samples.map((s) => s.y).reduce((a, b) => a + b) / samples.length;
    final double meanZ = samples.map((s) => s.z).reduce((a, b) => a + b) / samples.length;

    final List<double> mags = samples.map((s) {
      final dx = s.x - meanX;
      final dy = s.y - meanY;
      final dz = s.z - meanZ;
      return sqrt(dx * dx + dy * dy + dz * dz);
    }).toList();

    // Variance
    final double mean     = mags.reduce((a, b) => a + b) / mags.length;
    final double variance = mags
        .map((v) => pow(v - mean, 2).toDouble())
        .reduce((a, b) => a + b) / mags.length;

    // Peak (95th percentile)
    final sorted   = List<double>.from(mags)..sort();
    final int p95i = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    final double peak = sorted[p95i];

    // Median (50th percentile) — extra signal to help with calibration
    final int p50i = (sorted.length * 0.50).floor().clamp(0, sorted.length - 1);
    final double median = sorted[p50i];

    // Min / Max — useful for understanding the raw spread
    final double minMag = sorted.first;
    final double maxMag = sorted.last;

    // Decay rate
    final int earlyEnd  = (mags.length * 0.40).floor();
    final int lateStart = (mags.length * 0.60).floor();
    final double earlyMean = mags.sublist(0, earlyEnd).reduce((a, b) => a + b) / earlyEnd;
    final double lateMean  = mags.sublist(lateStart).reduce((a, b) => a + b) /
        (mags.length - lateStart);
    final double decay = earlyMean > 0.001
        ? ((earlyMean - lateMean) / earlyMean).clamp(0.0, 1.0)
        : 0.0;

    return {
      'label':    label,
      'variance': variance,
      'peak':     peak,
      'median':   median,
      'min':      minMag,
      'max':      maxMag,
      'decay':    decay,
      'samples':  samples.length,
    };
  }

  // ── Copy all readings to clipboard ─────────────────────────────────────────
  void _copyAll() {
    if (_readings.isEmpty) return;
    final buf = StringBuffer();
    buf.writeln('label\tvariance\tpeak\tmedian\tmin\tmax\tdecay\tsamples');
    for (final r in _readings) {
      if (r.containsKey('error')) {
        buf.writeln('${r['label']}\tERROR: ${r['error']}');
      } else {
        buf.writeln(
          '${r['label']}\t'
              '${_f(r['variance'])}\t'
              '${_f(r['peak'])}\t'
              '${_f(r['median'])}\t'
              '${_f(r['min'])}\t'
              '${_f(r['max'])}\t'
              '${_f(r['decay'])}\t'
              '${r['samples']}',
        );
      }
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Readings copied to clipboard (paste into Excel / Sheets)')),
    );
  }

  String _f(dynamic v) => (v as double).toStringAsFixed(5);

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Pocket Check Calibration',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_readings.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white70),
              tooltip: 'Copy all readings',
              onPressed: _copyAll,
            ),
          if (_readings.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              tooltip: 'Clear readings',
              onPressed: () => setState(() => _readings.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Status banner ────────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: _isRunning
                ? const Color(0xFFFFD700).withOpacity(0.15)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              children: [
                if (_isRunning) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Running: $_activeLabel …',
                    style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14),
                  ),
                ] else
                  const Text(
                    'Place phone in position, then tap the matching button.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // ── Scenario buttons ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _scenarios.map((s) {
                final isCurrent = _isRunning && _activeLabel == s.label;
                return GestureDetector(
                  onTap: _isRunning ? null : () => _runCheck(s.label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? s.color
                          : s.color.withOpacity(_isRunning ? 0.25 : 0.75),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(s.icon, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          s.label,
                          style: TextStyle(
                            color: Colors.white.withOpacity(_isRunning && !isCurrent ? 0.4 : 1.0),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // ── Column headers ───────────────────────────────────────────────
          if (_readings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: const [
                  Expanded(flex: 3, child: _ColHeader('SCENARIO')),
                  Expanded(flex: 2, child: _ColHeader('VAR')),
                  Expanded(flex: 2, child: _ColHeader('PEAK')),
                  Expanded(flex: 2, child: _ColHeader('MEDIAN')),
                  Expanded(flex: 2, child: _ColHeader('DECAY')),
                  Expanded(flex: 1, child: _ColHeader('N')),
                ],
              ),
            ),

          // ── Readings log ─────────────────────────────────────────────────
          Expanded(
            child: _readings.isEmpty
                ? const Center(
              child: Text(
                'No readings yet.\nRun a check above.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: _readings.length,
              itemBuilder: (context, i) {
                final r   = _readings[i];
                final idx = i + 1;
                final err = r['error'] as String?;

                // Find the scenario colour for the label badge
                final scenarioColor = _scenarios
                    .firstWhere(
                      (s) => s.label == r['label'],
                  orElse: () => const _Scenario('', Colors.grey, Icons.circle),
                )
                    .color;

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: scenarioColor.withOpacity(0.3),
                    ),
                  ),
                  child: err != null
                      ? Text(
                    '#$idx ${r['label']}: ERROR — $err',
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12),
                  )
                      : Row(
                    children: [
                      // Label
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 32,
                              decoration: BoxDecoration(
                                color: scenarioColor,
                                borderRadius:
                                BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '#$idx ${r['label']}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Variance — KEY metric
                      Expanded(
                        flex: 2,
                        child: _MetricCell(
                          value: r['variance'] as double,
                          decimals: 4,
                          highlight: true,
                        ),
                      ),
                      // Peak
                      Expanded(
                        flex: 2,
                        child: _MetricCell(
                          value: r['peak'] as double,
                          decimals: 3,
                          highlight: true,
                        ),
                      ),
                      // Median
                      Expanded(
                        flex: 2,
                        child: _MetricCell(
                          value: r['median'] as double,
                          decimals: 3,
                        ),
                      ),
                      // Decay
                      Expanded(
                        flex: 2,
                        child: _MetricCell(
                          value: r['decay'] as double,
                          decimals: 3,
                        ),
                      ),
                      // Sample count
                      Expanded(
                        flex: 1,
                        child: Text(
                          '${r['samples']}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Summary stats ────────────────────────────────────────────────
          if (_readings.length >= 2)
            _SummaryPanel(readings: _readings, scenarios: _scenarios),
        ],
      ),
    );
  }
}

// ─── Summary panel ────────────────────────────────────────────────────────────
// Groups readings by scenario label and shows mean variance + mean peak,
// which is exactly what you need to set _varianceMin/Max and _peakMin/Max.
class _SummaryPanel extends StatelessWidget {
  final List<Map<String, dynamic>> readings;
  final List<_Scenario> scenarios;

  const _SummaryPanel({required this.readings, required this.scenarios});

  @override
  Widget build(BuildContext context) {
    // Group by label
    final Map<String, List<Map<String, dynamic>>> byLabel = {};
    for (final r in readings) {
      if (r.containsKey('error')) continue;
      byLabel.putIfAbsent(r['label'] as String, () => []).add(r);
    }

    if (byLabel.isEmpty) return const SizedBox.shrink();

    return Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SUMMARY (mean across runs)',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...byLabel.entries.map((entry) {
            final label  = entry.key;
            final rows   = entry.value;
            final meanVar  = rows.map((r) => r['variance'] as double)
                .reduce((a, b) => a + b) / rows.length;
            final meanPeak = rows.map((r) => r['peak'] as double)
                .reduce((a, b) => a + b) / rows.length;
            final meanDecay = rows.map((r) => r['decay'] as double)
                .reduce((a, b) => a + b) / rows.length;

            final color = scenarios
                .firstWhere(
                  (s) => s.label == label,
              orElse: () => const _Scenario('', Colors.grey, Icons.circle),
            )
                .color;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '$label (${rows.length}×)',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'var: ${meanVar.toStringAsFixed(4)}',
                      style: const TextStyle(
                          color: Color(0xFFFFD700), fontSize: 11),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'peak: ${meanPeak.toStringAsFixed(3)}',
                      style: const TextStyle(
                          color: Color(0xFF80DEEA), fontSize: 11),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'decay: ${meanDecay.toStringAsFixed(3)}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          // Threshold hint
          const Text(
            '→ Set _varianceMin just below your lowest ON_PERSON mean.\n'
                '→ Set _varianceMax just above your highest ON_TABLE mean.\n'
                '→ Same logic for _peakMin / _peakMax.',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Small helpers ────────────────────────────────────────────────────────────
class _Scenario {
  final String    label;
  final Color     color;
  final IconData  icon;
  const _Scenario(this.label, this.color, this.icon);
}

class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(
      color: Colors.white30,
      fontSize: 10,
      letterSpacing: 1.0,
      fontWeight: FontWeight.bold,
    ),
  );
}

class _MetricCell extends StatelessWidget {
  final double value;
  final int    decimals;
  final bool   highlight;

  const _MetricCell({
    required this.value,
    required this.decimals,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) => Text(
    value.toStringAsFixed(decimals),
    textAlign: TextAlign.center,
    style: TextStyle(
      color: highlight ? Colors.white : Colors.white54,
      fontSize: 11,
      fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

// ─── Internal sample ──────────────────────────────────────────────────────────
class _RawSample {
  final double x, y, z;
  final DateTime time;
  const _RawSample(this.x, this.y, this.z, this.time);
}