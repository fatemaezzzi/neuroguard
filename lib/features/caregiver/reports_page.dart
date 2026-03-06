import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  static const TextStyle _bigBlack = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 22,
    letterSpacing: 1.5,
    color: Colors.black,
  );

  static const TextStyle _bigGreen = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 22,
    letterSpacing: 1.5,
    color: Color(0xFFCCFF00),
  );

  static const TextStyle _bigPurple = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 22,
    letterSpacing: 1.5,
    color: Color(0xFF7C3AED),
  );

  static const TextStyle _medBlack = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 16,
    color: Colors.black,
  );

  static const TextStyle _smallRoboto = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 13,
    color: Colors.black87,
  );

  static const TextStyle _smallRobotoBold = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w700,
    fontSize: 13,
    color: Colors.black,
  );

  static const TextStyle _timeStyle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Color(0xFFCCFF00),
  );

  static const TextStyle _bigNumber = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 36,
    color: Colors.white,
  );

  static const TextStyle _bigNumberBlack = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 36,
    color: Colors.black,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // ── SLEEP REPORT CARD ──────────────────────────────────
              _buildSleepReport(),
              const SizedBox(height: 20),

              // ── COGNITIVE TEST REPORT CARD ─────────────────────────
              _buildCognitiveReport(),
              const SizedBox(height: 20),

              // ── WEEKLY SUMMARY ─────────────────────────────────────
              _buildWeeklySummary(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── SLEEP REPORT ─────────────────────────────────────────────────────
  Widget _buildSleepReport() {
    return Stack(
      children: [
        // background blob
        Image.asset('assets/sleepreport.png',
            width: double.infinity, fit: BoxFit.fitWidth),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: const [
                    Text('SLEEP REPORT', style: _bigBlack),
                    SizedBox(width: 8),
                    Text('🌧️', style: TextStyle(fontSize: 22)),
                  ],
                ),
                const SizedBox(height: 10),

                // STATUS pill
                Stack(
                  children: [
                    Image.asset('assets/statusbed.png',
                        fit: BoxFit.fitWidth,
                        width: double.infinity),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('STATUS', style: _bigBlack),
                            Text('OCCUPIED/\nEMPTY',
                                textAlign: TextAlign.right,
                                style: _bigPurple),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Alert logs
                const Text('ALERT LOGS', style: _bigGreen),
                const SizedBox(height: 6),
                Row(
                  children: const [
                    Text('02:30  ', style: _timeStyle),
                    Text('Emergency Alert\n(Unresponsive)',
                        style: _smallRobotoBold),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: const [
                    Text('02:55  ', style: _timeStyle),
                    Text('Bed Exit Alert', style: _smallRobotoBold),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── COGNITIVE TEST REPORT ─────────────────────────────────────────────
  Widget _buildCognitiveReport() {
    return Stack(
      children: [
        Image.asset('assets/cognitivetestreport.png',
            width: double.infinity, fit: BoxFit.fitWidth),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('COGNITIVE TEST REPORT', style: _bigBlack),
                const SizedBox(height: 12),

                // Last test + Previous test row
                Row(
                  children: [
                    // LAST TEST — purple bg
                    Expanded(
                      child: Stack(
                        children: [
                          Image.asset('assets/lasttest.png',
                              width: double.infinity, fit: BoxFit.fitWidth),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('LAST TEST', style: _medBlack),
                                SizedBox(height: 4),
                                Text('2.8s', style: _bigNumber),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // PREVIOUS TEST — neon green bg
                    Expanded(
                      child: Stack(
                        children: [
                          Image.asset('assets/previoustest.png',
                              width: double.infinity, fit: BoxFit.fitWidth),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('PREVIOUS TEST', style: _medBlack),
                                SizedBox(height: 4),
                                Text('2.8s', style: _bigNumberBlack),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Hover time label
                const Text('HOVER TIME OVER LAST 5\nSESSIONS',
                    style: _bigBlack),
                const SizedBox(height: 10),

                // fl_chart
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
                  child: _buildHoverChart(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHoverChart() {
    final spots = [
      const FlSpot(1, 2.5),
      const FlSpot(2, 3.0),
      const FlSpot(3, 2.7),
      const FlSpot(4, 3.3),
      const FlSpot(5, 2.8),
    ];

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.5,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.grey.withOpacity(0.3),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontFamily: 'Roboto'),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 0.5,
              reservedSize: 36,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(1)}s',
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                    fontFamily: 'Roboto'),
              ),
            ),
          ),
          topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 1,
        maxX: 5,
        minY: 2.0,
        maxY: 3.5,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Colors.black87,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, pct, bar, idx) =>
                  FlDotCirclePainter(
                    radius: 4,
                    color: Colors.black87,
                    strokeWidth: 0,
                    strokeColor: Colors.transparent,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blueGrey.withOpacity(0.15),
            ),
          ),
        ],
      ),
    );
  }

  // ── WEEKLY SUMMARY ────────────────────────────────────────────────────
  // weeklysummary.png is the hourglass shape (top pill + bottom square connected)
  Widget _buildWeeklySummary() {
    return Stack(
      children: [
        Image.asset('assets/weeklysummary.png',
            width: double.infinity, fit: BoxFit.fitWidth),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: const Text('WEEKLY SUMMARY', style: _bigBlack),
            ),
          ),
        ),
      ],
    );
  }

  // ── BOTTOM NAV ────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          _NavCircle(iconAsset: 'assets/Vectorhome.png'),
          _NavCircle(iconAsset: 'assets/Vectorsettings.png'),
        ],
      ),
    );
  }
}

class _NavCircle extends StatelessWidget {
  final String iconAsset;
  const _NavCircle({required this.iconAsset});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset('assets/glassbubble.png',
              width: 62, height: 62, fit: BoxFit.cover),
          Image.asset(iconAsset, width: 28, height: 28),
        ],
      ),
    );
  }
}