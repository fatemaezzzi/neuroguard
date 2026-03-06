import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

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
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── SLEEP REPORT ──────────────────────────────────────────────────────
  Widget _buildSleepReport() {
    return LayoutBuilder(builder: (context, constraints) {
      final double w = constraints.maxWidth;
      // sleepreport.png is 364x307
      final double h = w * (307 / 364);
      // statusbed.png is 342x61
      final double sh = w * (61 / 342);

      return SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            // Background blob
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
                  // Title
                  Row(
                    children: const [
                      Text('SLEEP REPORT', style: _bigBlack),
                      SizedBox(width: 8),
                      Text('🌧️', style: TextStyle(fontSize: 22)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // STATUS pill — statusbed.png behind, text on top
                  SizedBox(
                    width: w - 40,
                    height: sh,
                    child: Stack(
                      children: [
                        Image.asset('assets/statusbed.png',
                            width: w - 40, height: sh, fit: BoxFit.fill),
                        Positioned.fill(
                          child: Padding(
                            padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
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

                  // Alert logs
                  const Text('ALERT LOGS', style: _bigGreen),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SizedBox(
                        width: 150,
                        child: Text('02:30', style: _timeGreen),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Emergency Alert\n(Unresponsive)',
                          style: _alertText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: const [
                      SizedBox(
                        width: 150,
                        child: Text('02:55', style: _timeGreen),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Bed Exit Alert', style: _alertText),
                      ),
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
      // cognitivetestreport.png is 364x307
      final double cardH = w * (307 / 364);
      // lasttest.png is 364x349 — very tall purple square
      // previoustest.png is 342x94 — neon green wide rect
      // We render them overlapping: previoustest behind, lasttest on top left
      final double ltW = w * 0.48;
      final double ltH = ltW * (349 / 364);
      final double ptH = ltW * (94 / 342);

      return SizedBox(
        width: w,
        // cognitive card must be tall enough to hold everything
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

                  // Last test + Previous test overlapping layout
                  _buildTestBoxes(w - 40),

                  const SizedBox(height: 16),

                  const Text('HOVER TIME OVER LAST 5\nSESSIONS',
                      style: _bigBlack),
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

  // LAST TEST purple rect (no image) overlaps ON TOP of previoustest.png
  Widget _buildTestBoxes(double w) {
    // previoustest.png: 342x94
    final double ptH = w * (94 / 342);
    // last test box: ~46% width, roughly square
    final double ltW = w * 0.30;
    final double ltH = ltW; // square-ish purple box

    return SizedBox(
      width: w,
      height: ltH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // PREVIOUS TEST — full width, vertically centered in the stack
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

          // LAST TEST — purple rounded rect, left half, ON TOP of previous test
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
              FlLine(color: Colors.grey.withOpacity(0.3), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontFamily: 'Roboto')),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 0.5,
              reservedSize: 38,
              getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(1)}s',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      fontFamily: 'Roboto')),
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
              getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
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
  // weeklysummary.png is 364x349 — hourglass (top pill + bottom square)
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
            // "WEEKLY SUMMARY" sits in the top pill portion (~top 27% of image)
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