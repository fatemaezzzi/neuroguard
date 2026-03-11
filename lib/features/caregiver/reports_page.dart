import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'cognitest_history_screen.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  static const TextStyle _bigBlack = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 28,
    letterSpacing: 1.0,
    color: Colors.black,
  );

  static const TextStyle _bigGreen = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 28,
    letterSpacing: 1.5,
    color: Color(0xFFCCFF00),
  );

  static const TextStyle _bigPurple = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 28,
    letterSpacing: 1,
    color: Color(0xFF7C3AED),
  );

  static const TextStyle _medBlack = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 15,
    letterSpacing: 1,
    color: Colors.black,
  );

  static const TextStyle _medWhite = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 15,
    letterSpacing: 1,
    color: Colors.white,
  );

  static const TextStyle _numberWhite = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 42,
    color: Colors.white,
  );

  static const TextStyle _numberBlack = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 42,
    color: Colors.black,
  );

  static const TextStyle _timeGreen = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: Color(0xFFCCFF00),
  );

  static const TextStyle _alertText = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 26,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: CaregiverBottomNav(
        onSettingsTap: () {},
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              _buildSleepReport(),
              const SizedBox(height: 20),
              _buildCognitiveReport(),
              const SizedBox(height: 20),
              _buildWeeklySummary(),
              const SizedBox(height: 20),
              _buildCognitiveHistory(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── SLEEP REPORT ──────────────────────────────────────────────────────
  Widget _buildSleepReport() {
    return LayoutBuilder(builder: (context, constraints) {
      final double w = constraints.maxWidth;
      final double h = w * (307 / 364);
      final double sh = w * (61 / 342);

      return SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            Image.asset('assets/sleepreport.png',
                width: w, height: h, fit: BoxFit.fill),
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Text('SLEEP REPORT', style: _bigBlack),
                      SizedBox(width: 8),
                      Text('🌧️', style: TextStyle(fontSize: 22)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: w - 40,
                    height: sh,
                    child: Stack(
                      children: [
                        Image.asset('assets/statusbed.png',
                            width: w - 40, height: sh, fit: BoxFit.fill),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: const [
                                Text('STATUS', style: _bigBlack),
                                Text('OCCUPIED',
                                    textAlign: TextAlign.right,
                                    style: _bigPurple),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('ALERT LOGS', style: _bigGreen),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SizedBox(width: 150, child: Text('02:30', style: _timeGreen)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Emergency Alert\n(Unresponsive)', style: _alertText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: const [
                      SizedBox(width: 150, child: Text('02:55', style: _timeGreen)),
                      SizedBox(width: 10),
                      Expanded(child: Text('Bed Exit Alert', style: _alertText)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ── COGNITIVE TEST REPORT ─────────────────────────────────────────────
  Widget _buildCognitiveReport() {
    return LayoutBuilder(builder: (context, constraints) {
      final double w = constraints.maxWidth;

      return SizedBox(
        width: w,
        child: Stack(
          children: [
            Image.asset('assets/cognitivetestreport.png',
                width: w, fit: BoxFit.fitWidth),
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('COGNITIVE TEST REPORT', style: _bigBlack),
                  const SizedBox(height: 14),
                  _buildTestBoxes(w - 40),
                  const SizedBox(height: 16),
                  const Text('HOVER TIME OVER LAST 5\nSESSIONS', style: _bigBlack),
                  const SizedBox(height: 10),
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 14, 14, 8),
                    child: _buildHoverChart(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildTestBoxes(double w) {
    final double ptH = w * (94 / 342);
    final double ltW = w * 0.30;
    final double ltH = ltW;

    return SizedBox(
      width: w,
      height: ltH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: ltH / 2 - ptH / 2,
            left: 0,
            right: 0,
            height: ptH,
            child: Stack(
              children: [
                Image.asset('assets/previoustest.png',
                    width: w, height: ptH, fit: BoxFit.fill),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: const [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('PREVIOUS TEST', style: _medBlack),
                            SizedBox(height: 2),
                            Text('2.8s', style: _numberBlack),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            width: ltW,
            height: ltH,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.fromLTRB(14, 16, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('LAST TEST', style: _medWhite),
                  Text('2.8s', style: _numberWhite),
                ],
              ),
            ),
          ),
        ],
      ),
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
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.grey.withValues(alpha: 0.3), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54, fontFamily: 'Roboto')),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 0.5,
              reservedSize: 38,
              getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(1)}s',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black54, fontFamily: 'Roboto')),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
              getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                radius: 4,
                color: Colors.black87,
                strokeWidth: 0,
                strokeColor: Colors.transparent,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blueGrey.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  // ── COGNITIVE HISTORY BUTTON ──────────────────────────────────────────
  Widget _buildCognitiveHistory() {
    return LayoutBuilder(builder: (context, constraints) {
      final double w = constraints.maxWidth;
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CogniTestHistoryScreen(),
            ),
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/cognitivehistorybutton.png',
              width: w,
              fit: BoxFit.fitWidth,
            ),
            const Text('COGNITIVE HISTORY', style: _bigBlack),
          ],
        ),
      );
    });
  }

  // ── WEEKLY SUMMARY ────────────────────────────────────────────────────
  Widget _buildWeeklySummary() {
    return LayoutBuilder(builder: (context, constraints) {
      final double w = constraints.maxWidth;
      final double h = w * (349 / 364);
      return SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            Image.asset('assets/weeklysummary.png',
                width: w, height: h, fit: BoxFit.fill),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: h * 0.23,
              child: const Center(
                child: Text('WEEKLY SUMMARY', style: _bigBlack),
              ),
            ),
          ],
        ),
      );
    });
  }
}